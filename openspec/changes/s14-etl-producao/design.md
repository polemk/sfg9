# Design: S14 — o ETL de produção

> O mapa item-a-item **não é duplicado aqui**. Fonte: `.migration-ai9/map/data-infra.md`
> §2.1 (linhas `DB-ETL-*`, `OPS-546..549`, `DB-597`, `DB-599`, `DB-738`), §2.7
> (`BE-450..454`, `DB-434`), §5 (runbook do schema), §6 (Q-07, Q-11, Q-16) e §7 (F-08).
> Desenho do seed que serve de banco de ensaio: `.migration-ai9/demo-seed-design.md`.

## Context

O que existe hoje: um banco Rails de produção do Safegold (2016–2026), com **uma** foreign
key em todo o schema, sem índice único nas 20+ unicidades compostas, com timestamps gravados
em horário de Brasília (`default_timezone = :local`) e com anomalias herdadas de um ETL
Django→Rails executado uma única vez em 2021.

O que existe no destino: `backend/db/schema.rb` versionado, **52 tabelas** declaradas com
**40 migrations** — a diferença é o que foi editado à mão no trim, mais **~25 tabelas
órfãs** herdadas da base ai9 (`fly_*`, `work_*`, `budget*`, `achievements`,
`user_achievements`, `drops`, `point_events`), sem model, sem migration e sem referência
(**C-07**).

Essas ~25 órfãs **não são cosmética**: elas contaminam o baseline de introspecção. Se o
DB-ETL-01 comparar "o `schema.rb` inteiro" com "o esperado", ele aborta contra o **próprio
destino**. O baseline correto é **o schema derivado das migrations do Safegold**.

## Goals / Non-Goals

**Goals**
- Um script **idempotente, em lotes, retomável**, com dry-run e reconciliação — nesta ordem,
  porque cada propriedade depende da anterior.
- Que **nenhuma decisão de dado seja tomada dentro da janela de cutover**. Tudo o que exige
  julgamento humano aparece no relatório de dry-run, dias antes.
- Um **runbook** que outra pessoa consegue executar, com portões de go/no-go explícitos e um
  procedimento de rollback que não depende de improviso.

**Non-Goals**
- **Não** portar o ETL de 2021 (DEC-12) — nem como referência de código, só como registro do
  comportamento que produziu os dados.
- **Não** reprocessar papéis definidos em 2021 (Q-16). O dry-run lista; o humano decide.
- **Não** corrigir dado do cliente por conta própria. Anomalia vira **linha de relatório**,
  nunca `UPDATE` silencioso.

## Decisions

### E1. Cinco fases, e cada uma tem um artefato

```
introspect  →  dry-run  →  load  →  reconcile  →  cutover (runbook)
   ↓             ↓          ↓          ↓
 relatório    relatório   log de    relatório
 de schema    de dados    lotes     de conferência
```

Comandos versionados em `backend/lib/tasks/sfg_etl.rake`:
`sfg_etl:introspect`, `sfg_etl:dry_run`, `sfg_etl:load`, `sfg_etl:reconcile`,
`sfg_etl:status`. Hoje `backend/lib/tasks/` tem **um** arquivo — o padrão nasce aqui, e
`OPS-632` pede isso nominalmente.

**Cada fase produz arquivo, não só saída de terminal.** Relatório em arquivo é versionável,
comparável entre execuções e anexável à aprovação do cutover. Saída de terminal desaparece
com a janela do SSH.

### E2. Introspecção: o baseline é o schema das migrations, não o `schema.rb`

DB-ETL-01. Como não haverá `pg_dump --schema-only` (DEC-04), a introspecção lê o schema
**real** da origem no momento da execução — tabelas, colunas, tipos, índices — e compara com
o esperado. Qualquer desconhecido **aborta com relatório** nomeando tabela, coluna e tipo.

Duas provas de que o schema real diverge das migrations **eram tidas como conhecidas** e
entram no mapeamento explícito, para não abortarem a carga: `default_position` (**D-06**) e
`contracts.description` (**D-108**). Uma **terceira** surpresa aborta — é exatamente esse o
valor da etapa.

> **CORREÇÃO, medida contra o dump de produção em 26/08/2026: nenhuma das duas existe.**
> `default_position` aparece **zero vez** no dump inteiro (continua sendo o defeito D-126:
> `order!(default_position: :asc)` contra coluna inexistente). `contracts` tem **7 colunas** e
> nenhuma `description` — o `description` do contrato é `has_rich_text` (`contract.rb:11`),
> ou seja **ActionText**, com 2 linhas em `action_text_rich_texts`. **O D-108 muda de
> veredito e deixa de ser evidência de schema fora do versionamento — não existe schema fora
> das migrations no Safegold.** A allowlist fica: ela descreve o que é *tolerado*, não o que
> existe, e foi ela que permitiu identificar como falsos positivos as 7 "surpresas" que um
> baseline incompleto produziu (`improvements-log.md` ETL-S14-11).
>
> A etapa provou o valor dela mesmo assim: contra o dump real, **0 surpresas** depois do
> baseline corrigido, sobre 56 tabelas e 782.742 linhas.

Do lado do destino, o baseline exclui as **30** órfãs herdadas por **allowlist explícita** (o texto original dizia ~25; contadas, são 30 — `improvements-log.md` ETL-S14-03). Allowlist,
não filtro por prefixo: assim uma órfã **nova** falha a build, e as antigas ficam visíveis em
vez de esquecidas.

### E3. De-para persistido é o que torna tudo o resto possível

DB-ETL-02. `etl_id_map (source_table, legacy_pk, ai9_id)` com **índice único
`[source_table, legacy_pk]`**. Ele resolve três problemas de uma vez:

1. **Religamento correto.** O legado tem uma FK; o ai9 usa `uuid` em parte das tabelas.
   Religar por id numérico associa registro errado em silêncio.
2. **Idempotência.** Rodar de novo consulta o de-para antes de inserir: quem já tem
   correspondência é **atualizado ou pulado**, nunca duplicado. É a propriedade que o ETL de
   2021 não tinha — rodar duas vezes **duplicava tudo**, exceto usuários.
3. **Auditoria depois do cutover.** Junto com as colunas `legacy_*` (DB-ETL-05, BE-451), é a
   prova de proveniência dos borderôs de 2016–2021.

Referência sem correspondência **não vira referência inventada**: é contada como órfã e cai
na regra do DB-ETL-03.

### E4. Lotes e retomada: o cutover não pode depender de a conexão sobreviver

Nenhum requirement existente descreve isto, e é onde ETLs falham na prática. Desenho:

- Carga **por tabela, em lotes** de tamanho configurável, ordenados por chave primária da
  origem — ordem estável entre execuções.
- Uma **tabela de checkpoint** grava `(execução, tabela, último_pk_processado, contagem,
  estado)` ao fim de **cada lote**, na mesma transação do lote.
- `sfg_etl:load` retomado depois de queda **continua do último checkpoint**, não do começo.
  `sfg_etl:status` diz onde parou.
- **Transação por lote, não por tabela inteira** — transação de 1,2 milhão de linhas segura
  lock e, se cair no fim, joga fora horas de trabalho.
- **Ordem de carga derivada das dependências**, com o precedente do legado como piso: as 12
  entidades de `Legacy::TABLES` (carriers → segments → receivable_kinds → wallets →
  resource_sources → movement_kinds → users → projects → memberships →
  project_to_carrier_connections → receivable_entries → receivable_taxes) mais o que o
  Safegold ganhou depois de 2021 (risco, estruturadas, renegociações, indicadores,
  disponibilidades).

### E5. Hierarquia de papel: tabela de-para explícita, **nunca** fórmula

Contrato **C3**, e o item de maior risco da migração. A escala é **invertida**:

| Legado (`hierarchy`, maior = mais poder) | ai9 (`hierarchy_level`, menor = mais poder) |
| ---------------------------------------- | ------------------------------------------- |
| OG 1111 | OG 1 |
| Admin 998 | Admin *(nível do seed)* |
| Gerente 888 | Gerente *(nível do seed)* |
| Colaborador 799 | Colaborador *(nível do seed)* |

A tabela literal vem do seed de papéis (S0/`auth-users`); o ETL **a consome**, não a
recalcula. Regras:

- **Valor de origem fora da tabela → a linha aborta o lote e aparece no relatório.** Uma
  fórmula faria o contrário: sobreviveria ao valor inesperado e produziria um nível
  **plausível e errado**.
- O teste verifica **os dois lados**: "Admin NÃO edita ability de OG" **e** "Admin EDITA
  ability de Colaborador". Um teste que só verifica que a trava existe passa com o sinal
  invertido — porque a trava existe, apontando para o lado errado.
- **Q-16, confirmada na fonte** (`../sfg/app/models/legacy/u.rb:33`):
  `i.is_staff ? MANAGER : i.is_superuser ? ADMIN : COLAB` — equipe tem precedência sobre
  superusuário. Usuários ativos podem estar com papel errado **desde 2021**. Decisão: **não
  reprocessar**; o dry-run **lista** quem está nessa condição, com o par
  `(is_staff, is_superuser)` da origem, para revisão humana.

### E6. Dry-run: tudo que exige julgamento humano acontece aqui

DB-ETL-03 e o relatório que o runbook usa como portão. Uma seção por tabela, contendo:

| Conferência | O que reporta |
| ----------- | ------------- |
| Órfãos | Tabela, coluna, quantidade e **amostra de ids** |
| Duplicatas | As 20+ unicidades compostas que o legado só validava em aplicação (ex.: duas `availability_entries` com mesma data/projeto/empresa/template) |
| Booleanos fora de `{0,1}` | Regra transversal **D-E** — todo `int 0/1` vira `boolean`, e o que não for 0 nem 1 é reportado **antes** de converter |
| Enums-string em pt-BR | BE-445 e BE-448: "Diferença"/"OK" e as naturezas de `movement_kind` gravadas como texto — conversão listada linha a linha |
| Timestamps ambíguos | As horas que aconteceram duas vezes na virada do DST (DB-ETL-04) |
| Papéis suspeitos | Os usuários afetados por Q-16 |
| Anexos | Registro cujas colunas Paperclip indicam arquivo que **não existe no disco de origem** (DB-482) |
| Truncamentos | `street_number` int → string (**D-V**), e qualquer campo cuja origem já esteja truncada |
| `smart_id` | Os **dois formatos** que convivem (o resquício MySQL `16777214`) |

**Contagem > 0 sem decisão registrada = aborta.** Com decisão registrada, a carga prossegue e
o relatório final informa quantas linhas foram descartadas ou corrigidas por aquela decisão.

### E7. Timestamps: transições da tz database, nunca offset fixo

DB-ETL-04. **Não existe um `AT TIME ZONE` único que sirva**: houve horário de verão até
2019-02-16 e depois UTC-3 constante. A conversão usa as transições de `America/Sao_Paulo`
(DEC-06).

A verificação que fecha o assunto é amostral e por ano: para uma amostra de cada ano de 2016
a 2026, o instante convertido, **reexibido em `America/Sao_Paulo`, mostra exatamente a mesma
hora local que o legado mostra hoje na tela**. É um oráculo observável, não uma conta.

### E8. Precisão financeira: o defeito vai junto, de propósito

DB-ETL-06 e **DEC-02**. O ai9 replica **a mesma sequência de operações, os mesmos casts e os
mesmos pontos de arredondamento** — incluindo `remunerations.value` e `receipts.fee` em
**float** multiplicando `decimal(15,2)`, e as ~30 taxas float de `receivable_entries`. A
precisão é uma melhoria **declinada**: se os totais não baterem com o legado, o cliente não
confia em nada mais.

Decisão **D-H**: mantém-se `decimal(15,2)` (reduzir pode truncar valor existente) e
mantém-se float onde o legado tem float. Decisão **D-G**: as colunas em pt-BR das tabelas
transacionais (`valor_bruto`, `qtd_titulos`, `nro_bordero`) **preservam o nome** — o ETL fica
1:1 e a conferência de paridade fica legível.

O oráculo são os **testes golden de fórmula** (contrato **C2**), escritos pelos blocos de
domínio com valores extraídos do legado em Ruby 2.6.1 / Rails 6.0.3.2 (DEC-11). O ETL não
inventa oráculo próprio: ele **reusa** o que trava a build.

### E9. Reconciliação: contagem **e** amostra, por tabela

Contagem sozinha é fraca — 1000 linhas migradas com valor errado dão contagem certa.
Portanto, por tabela:

1. **Contagem** origem × destino, com a diferença explicada linha a linha quando houver
   (descarte por decisão registrada é diferença **esperada**, e aparece como tal).
2. **Amostra determinística** (semente fixa) de N registros por tabela, comparados
   **campo a campo** entre origem e destino, com a conversão aplicada.
3. **Somatórios financeiros** por tabela e por ano: `valor_bruto`, saldos de operação,
   valores de remuneração e de recibo. É o teste que pega erro de cast e de sinal.
4. **Contagem de referências religadas** por FK: quantas resolveram pelo de-para e quantas
   caíram em órfã.

O relatório de reconciliação é **assinado por um humano** no runbook. Sem essa assinatura,
não há cutover.

### E10. O ETL é exercitado contra o seed de demo antes de ver dado real

DEC-16, item 3, e o próprio `demo-seed-design.md` §12 diz isso. O seed é determinístico
(`Random.new(20260828)`), idempotente e **fecha aritmeticamente** — as 7 regras de coerência
da §7 do desenho. Isso o torna um banco de ensaio com propriedades **conhecidas**: dá para
afirmar que a reconciliação está certa, porque se sabe qual é a resposta.

Ordem: `demo:seed` → `sfg_etl:dry_run` → `sfg_etl:load` → `sfg_etl:reconcile` → **rodar de
novo** e provar que nada duplicou.

### E11. O portão de `db:migrate` × `schema.rb`

Fatia S-00 do mapa, §5 — e a razão dela existir é um incidente real: **+485 linhas**
reintroduzidas por um `db:migrate` contra banco desatualizado, revertidas depois.

Procedimento obrigatório (vira item de runbook e de checklist de PR):

1. Antes de qualquer `db:migrate`: `git status --porcelain backend/db/schema.rb` limpo.
2. Rodar a migration.
3. **Imediatamente depois:** `git diff backend/db/schema.rb`.
4. **Ler o diff.** Qualquer coisa além do que a migration cria → `git checkout --
   backend/db/schema.rb`, recriar o banco (`db:drop db:create db:schema:load`) e repetir.
5. Nunca commitar `schema.rb` sem ter lido o diff inteiro.

Portão automatizado: um teste que falha se o `schema.rb` declarar tabela que **nenhuma
migration** cria, com **allowlist explícita** das ~25 órfãs. E no CI (quando existir —
`.github/workflows/ci.yml` está vazio, `upstream-flags` #1): `db:schema:load` em banco limpo,
`db:migrate`, `git diff --exit-code backend/db/schema.rb`.

### E12. Descarte com evidência é entregável, não burocracia

15 dos 24 IDs desta fatia são `drop`. A regra: **cada um vira uma linha do
`parity-ledger.md` com a prova** — arquivo, linha, ou o comando que produz a contagem. Uma
auditoria futura precisa distinguir "decidimos não portar, aqui está o porquê" de "ninguém
viu". A segunda é indistinguível de perda de feature.

## Risks / Trade-offs

| Risco | Mitigação |
| ----- | --------- |
| **Fórmula de hierarquia em vez de tabela** — produz nível plausível e errado, e passa em teste ingênuo | Tabela de-para explícita; valor fora da tabela **aborta**; teste verifica os **dois** lados da comparação (C3) |
| **`db:migrate` re-dumpando o `schema.rb`** — já custou +485 linhas | Procedimento E11 + teste de portão + item de CI |
| **Introspecção abortando contra o próprio destino** por causa das ~25 órfãs (C-07/F-08) | Baseline = schema **derivado das migrations**, com allowlist explícita das órfãs |
| **Sem acesso ao disco do servidor legado** (Q-11) os 11 anexos não migram — só os registros | Caminho parametrizado e exercitado contra o seed; o passo real fica **bloqueado por dependência externa** no runbook, e isso é dito, não silenciado |
| **Reconciliação só por contagem** deixa passar valor errado | Contagem **e** amostra campo a campo **e** somatório financeiro por ano |
| **Anomalias de 2021 "consertadas" por conta própria** durante a carga | Anomalia vira linha de relatório. Nenhum `UPDATE` de correção sem decisão registrada e assinada |
| **Janela de cutover virando sessão de depuração** | Todo julgamento humano acontece no dry-run, dias antes. O `load` da janela só executa decisões já tomadas |
| **Rollback improvisado** | O runbook exige backup verificado (restaurado em ambiente separado, não só criado) **antes** do primeiro `load` |
