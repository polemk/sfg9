# Proposal: S14 — ETL de produção: introspecção, dry-run, reconciliação e runbook

> Fatia **S14** da ordem de execução de `.migration-ai9/migration-map.md` — a **última**, e a
> que depende de todas.
> Bloco de origem: `.migration-ai9/map/data-infra.md` — fatias internas **S-15** (ETL),
> **S-00** (runbook do schema) e **S-17** (descartes com evidência).

## Why

Esta é a fatia com **maior risco de dado** da migração inteira. Tudo o que veio antes pode
ser corrigido com um deploy; um ETL errado grava número errado no banco do cliente e ninguém
percebe — porque o número **parece** plausível.

Três medições explicam por que o script precisa ser desenhado, e não improvisado na janela
de cutover:

1. **O legado tem exatamente uma foreign key em todo o schema**
   (`active_storage_attachments.blob_id`) e nenhum índice único nas 20+ unicidades compostas
   que ele só validava em aplicação. Religar referência por id numérico associa registro
   errado **em silêncio** (DB-ETL-02, DB-ETL-03).
2. **O ETL anterior — Django → Rails, 2021 — é o anti-exemplo, e seus efeitos estão nos
   dados de produção de hoje.** Lido na fonte: `../sfg/app/models/legacy.rb` fixa uma ordem
   obrigatória de **12 entidades**, o log é desligado durante a execução, erros de validação
   são apenas impressos (sem abortar, sem reverter), não há transação e não há idempotência
   — **rodar duas vezes duplicava tudo**, exceto usuários, que eram buscados por e-mail.
   Ele também gravou anomalias que continuam lá: autor forçado para um id fixo em portadores
   e recebíveis, empresa forçada para um id fixo "por questão de portabilidade", o
   responsável do projeto caindo em cascata até um **e-mail de pessoa real embutido no
   código**, e a senha de **todo** usuário derivada do primeiro nome
   (`"#{transliterate(primeiro_nome).downcase}#6230"`, `app/models/legacy/u.rb:31`).
3. **A conversão de hierarquia de papel é o item que mais pode dar errado.** A escala é
   **invertida** entre os dois sistemas (contrato **C3**): no legado **maior = mais poder**
   (OG 1111 > Admin 998 > Gerente 888 > Colaborador 799); no ai9 **menor = mais poder**
   (`user_type.rb:38-41`, OG = 1). Uma fórmula de conversão **sobrevive a valor inesperado e
   produz nível plausível e errado** — e passa em qualquer teste que verifique só que "a
   trava existe", porque a trava existe: está apontando para o lado errado. Por isso a
   conversão é **tabela de-para explícita, nunca fórmula**.

E há uma armadilha do próprio repositório que esta fatia transforma em portão: **os blocos do
Phase 1b editaram `backend/db/schema.rb` à mão**, sem migration de `drop` (decisão de
design). Rodar `db:migrate` contra um banco desatualizado faz o Rails **re-dumpar o banco
real** por cima do `schema.rb` e reintroduzir tudo que foi removido. **Já aconteceu: +485
linhas, revertidas.**

## What Changes

**24 IDs**, mais **5 adotados no fechamento do Phase 2** (ver a seção correspondente no fim
deste documento). O mapa item-a-item está em `.migration-ai9/map/data-infra.md` §2.1 (linhas
`DB-ETL-*`, `OPS-546..549`, `DB-597`, `DB-599`, `DB-738`) e §2.7 (`BE-450..454`, `DB-434`).

### A. O motor de ETL — 7 IDs, todos `build`

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| DB-ETL-01 | build | Introspecção do schema **real** da origem, comparado com o esperado das 139 migrations; **aborta com relatório** ao achar desconhecido. Duas provas já conhecidas: `default_position` (D-06) e `contracts.description` (D-108) |
| DB-ETL-02 | build | Tabela de-para persistida `etl_id_map (source_table, legacy_pk, ai9_id)` com índice único — é o que torna a carga **idempotente** e o religamento correto |
| DB-ETL-03 | build | Contagem de **órfãos** e **duplicatas** antes de inserir; aborta se > 0 sem decisão registrada |
| DB-ETL-04 | build | Timestamps para UTC pelas **transições da tz database** de `America/Sao_Paulo`, nunca offset fixo (houve DST até 2019-02-16) |
| DB-ETL-05 | build | Colunas `legacy_*` preservadas — a **única** prova de proveniência dos borderôs de 2016–2021 |
| DB-ETL-06 | build | Precisão financeira replicada: mesma sequência de operações, mesmos casts, mesmos pontos de arredondamento (DEC-02) |
| BE-451 | build | Rastreabilidade pelo identificador legado, com índice único onde o legado já tinha |

**Correção ao requirement:** `DB-ETL-05` em `openspec/specs/data-schema/spec.md` manda
preservar também `legacy_password`. O mapa **revoga** isso (§2.1, e BE-453): a senha de todo
usuário importado é **derivada do primeiro nome** — previsível — e o ai9 autentica por magic
link/código (DEC-14). **`legacy_password` não existe no ai9.** A divergência está registrada
aqui de propósito, para o QA do Phase 4 não a ler como item faltando.

### B. Runbook do schema e do cutover — 3 IDs

`OPS-549` (**reuse** — o `schema.rb` do ai9 já é versionado, ao contrário do legado, onde
está no `.gitignore:15`; o que esta fatia acrescenta é **o portão**), `DB-738` (**reuse** —
`ar_internal_metadata` é a guarda de `db:drop`/`db:schema:load` por ambiente), `DB-599`
(**drop** — `schema_migrations` do legado não é migrada; o ai9 gera a sua).

### C. Descartes com evidência — 15 IDs

Nenhum produz código. Todos produzem **prova registrada**, porque `dropped` por omissão é
indistinguível de esquecimento numa auditoria.

| ID | Motivo registrado |
| -- | ----------------- |
| BE-450 | Pipeline de importação **não portado como código de aplicação** (DEC-12). Fica registrado o comportamento: 12 entidades em ordem obrigatória, log desligado, erros só impressos, sem transação e sem idempotência |
| BE-452 | As três anomalias que **estão nos dados de produção**: autor fixo em portadores e recebíveis, empresa fixa em recebíveis, responsável do projeto caindo num e-mail de pessoa real no código |
| BE-453 | Senha derivada do primeiro nome + sufixo fixo, e senha do sistema anterior preservada em coluna própria. O esquema não é portado |
| BE-454 | As 4 correções pós-importação desligavam o log e devolviam sucesso cego; a comparação de papel era por **texto literal**; a última carregava todos os recebíveis em memória e os re-gravava um a um; e **a terceira sobrescreve o responsável definido pela segunda** — a ordem importa e não estava documentada |
| DB-434 | Duas conexões abertas em produção, a segunda apontando para a base histórica em português, **com senha em texto puro no repositório** |
| OPS-546 | `db/seed_assets/sfg_legacy_full.sql` (9 MB) é a fonte **original** dos dados que já estão no banco Rails: portar seria **reimportar** |
| OPS-547 | `app/models/legacy.rb` + 17 arquivos de `app/models/legacy/`: executado **uma única vez, em 2021** (o banco `SG20210329` traz a data no nome) |
| OPS-548 | A conexão `sfg_legacy` está declarada nos **5** arquivos de exemplo do legado, inclusive o de produção. O ai9 tem **uma** conexão |
| DB-597 | `delayed_jobs` não é importada — Sidekiq não tem registro relacional (o par deste descarte é o da tabela do legado, fechado em S13 — ver Fronteiras) |
| DB-599 | `schema_migrations` do legado não é migrada |
| OPS-630 | `config/resources.yml` (com `operating_hours` e um campo `sex`) **não é lido por nenhum código** |
| OPS-636 | `public/mailtest.html` (706 linhas, título "Criação de empressa", com **ERB não processado**) não é portado |
| BE-364 | Rotas e actions mortas da central de ajuda — capability `help-faq` (S12 não tem tarefa de código para elas; a evidência é registrada aqui para não ficarem órfãs) |
| ENG-navkit | A engine **não carrega** no legado. Três provas independentes: falta o arquivo de entrada `livetat_navkit.rb` (e o `Bundler.require` engole o `LoadError` porque o nome não tem `-`); `navkit.rb:1` faz `require "livetat_ux_kit"`, inexistente; o JS/CSS só é importado por um pack referenciado pelo layout de login |
| ENG-auth_omni19 | O login social **não funciona**: credenciais são placeholders (`FACEBOOK_APP_ID = 0`, cookie `fbsr_0`) e o seletor `.facebook_button` **não existe em nenhum HTML** |

## Os `build?` desta fatia

**Zero.** Os 16 `build?` do bloco `data-infra` estão em S13 (13, sendo 12 do portão Q-04) e
os outros 3 em **S12** (ajuda de campo) e **S17** (os dois de tema) — os IDs estão nomeados
na seção "Fronteiras", com o dono ao lado. Nenhum item de ETL está em dúvida de
existir — o que está em aberto é **dependência externa**, não decisão de escopo: **Q-11**
(acesso ao disco do servidor legado, sem o qual os arquivos não migram — só os registros) e
**Q-16** (a precedência de papel do adaptador de 2021 estava invertida).

**Q-16 foi confirmada lendo a fonte.** `../sfg/app/models/legacy/u.rb:33`:

```ruby
o.role_type = i.is_staff ? ::U.MANAGER : i.is_superuser ? ::U.ADMIN : ::U.COLAB
```

A marca de **equipe** tem prioridade sobre a de **superusuário** — um `is_superuser` que
também fosse `is_staff` virou **Gerente**, não Admin. Isso definiu papéis de usuários que
**ainda estão ativos**. Decisão registrada: **não reprocessamos papéis**; o dry-run
**lista** os usuários nessa condição para revisão humana antes do cutover.

## Fronteiras — o que este change **não** cobre

- **O schema de destino.** As tabelas nascem em S3..S12. O ETL **carrega**, não cria.
- **O seed de demonstração** (`db/seeds/demo/` + `rake demo:seed`) — é a fatia S-16 do mapa
  de bloco, e desenho pronto em `.migration-ai9/demo-seed-design.md`. **S14 o consome**: o
  ETL é exercitado contra o banco do seed **antes de ver dado real** (DEC-16, item 3).
- **Os testes golden de fórmula financeira** — são contrato **C2**, escritos pelos blocos de
  recebíveis, risco e estruturadas. DB-ETL-06 **os reusa** como oráculo de reconciliação.
- **O motor de anexos** — S13. O ETL de arquivos (DB-482) depende dele.
- **Rotação das credenciais comprometidas** (senha da conexão `sfg_legacy`, senha do banco
  em `database.linux.yml:8,25`) — ação do usuário, fora deste repositório.

## Dependências

- **Depende de todas as fatias** — não há como carregar o que não tem tabela.
- **Depende de S13** para os anexos e para saber que jobs pendentes no cutover **não** são
  importados (DB-460).
- **Depende do seed de demo** para poder ser exercitado sem dado real.
- **O runbook depende de Q-07** (storage de produção) e **Q-11** (acesso ao disco legado).
  Sem resposta, o passo de arquivos fica **parametrizado e testado contra o seed**, e o
  runbook o marca como **bloqueado por dependência externa** — não como concluído.

## Capabilities

### New Capabilities

Nenhuma. Os requirements existem em `openspec/specs/data-schema/` desde o Phase 1 e são
referenciados **por ID**.

### Modified Capabilities

- `data-schema`: **quatro** requirements novos, todos cobrindo lacunas reais do conjunto
  `DB-ETL-01..06` — que descreve *o que* converter, mas não *como executar sem estragar*:
  execução em lotes/idempotente/retomável, conversão de hierarquia de papel por tabela
  de-para, runbook de cutover com reconciliação aprovada, e o portão de `db:migrate` ×
  `schema.rb`.

## Impact

- **Backend:** `backend/lib/sfg_etl/**` (introspecção, de-para, carga por tabela, conversores,
  reconciliação) e `backend/lib/tasks/sfg_etl.rake` (`introspect`, `dry_run`, `load`,
  `reconcile`, `status`). Hoje `backend/lib/tasks/` tem **um** arquivo
  (`export_startpoint.rake`) — o padrão nasce aqui.
- **Dados:** tabela `etl_id_map` e uma tabela de checkpoint de execução. **Nenhuma tabela de
  domínio é criada por esta fatia.**
- **Repositório:** teste de portão do `schema.rb` (com allowlist explícita das ~25 tabelas
  órfãs herdadas — **C-07**/F-08) e o runbook versionado.
- **Não afetado:** nada do legado (read-only). Nenhuma refatoração da base ai9.
- **Paridade:** 9 IDs viram código, 15 viram `dropped` com evidência — soma **24**.


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-073 | build | **Ausência de `db/schema.rb` no legado** → etapa de **introspecção** do ETL: o esquema de origem é lido do banco, não de arquivo | S14 é dona do motor de ETL |
| DB-074 | build | **Volumes** → relatório de volumetria por tabela, produzido antes da carga | idem |
| DB-598 | reuse | `active_storage_blobs` — a base ai9 já tem; a tabela não é recriada, e o ETL **conta** antes de decidir | idem |
| DB-736 | reuse | `active_storage_attachments` — idem | idem |
| DB-737 | reuse | `action_text_rich_texts` — idem | idem |

**`DB-073` é a razão de a introspecção existir.** O legado tem `schema.rb` no `.gitignore`:
não há arquivo que descreva o esquema de origem, e qualquer suposição sobre coluna é
suposição. O ETL **lê o banco**.

**Os três `reuse` de ActiveStorage/ActionText são fontes de ETL, não tabelas a construir** —
é a distinção que separa esta fatia das fatias de domínio. Uma tabela do legado que **vira
tabela no ai9** é da fatia que constrói a entidade; uma tabela que é apenas **lida** é daqui.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`BE-364` é de S14** — disputado com S12. As rotas e actions mortas da central de ajuda
  são `drop`, S12 não tem tarefa de código para elas, e a evidência é registrada **aqui**,
  junto dos demais descartes com prova. Sem isso, o ID cairia entre as duas fatias.
- **`DB-460` é de S13**, não desta fatia: a tabela `delayed_jobs` e as colunas de progresso
  são fechadas lá. S14 registra apenas o seu par — a não importação da tabela — em `DB-597`.
- **`BE-379` e `BE-382` são de S17.** Este proposal os listava como "S12/tematização", e S13
  fazia o mesmo apontando para "S2": duas fatias apontando para fora, e nenhuma delas
  existia. Agora o dono é a fatia de temas.
- **`OPS-545` é de S12** — mecanismo de ajuda por campo. S14 apenas a cita.
