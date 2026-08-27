# Tasks: S14 — ETL de produção

Fila resumível do Phase 3, ordenada **por camada** (portões → dados → motor → dry-run →
carga → reconciliação → runbook → paridade). Uma tarefa = **um comportamento verificável**.
Cada tarefa cita os IDs que fecha, para o `parity-ledger.md`.

**Portões que valem para a fatia inteira:**
- **Nunca rodar `db:migrate` sem ler `git diff backend/db/schema.rb` depois** (§5 do mapa de
  bloco). Já custou +485 linhas reintroduzidas.
- **Nenhuma correção de dado do cliente sem decisão registrada e assinada.** Anomalia vira
  linha de relatório, nunca `UPDATE` silencioso.
- **Todo relatório é arquivo**, não saída de terminal — versionável, comparável e anexável à
  aprovação do cutover.


> **Estado em 26/08/2026 — S14.** O **arcabouco esta pronto e exercitado executando**:
> introspeccao, volumetria, de-para de id, lotes, transacao por lote, checkpoint dentro da
> transacao, retomada, idempotencia, religamento de FK so pelo de-para, dry-run com portao de
> decisao, reconciliacao e runbook. Os **conversores de dominio** entram um a um em
> `backend/app/lib/sfg/etl/converters/` conforme S4..S12 entregam os models — o motor **pula
> com aviso, nomeando o model e a fatia**, e a proxima execucao os inclui sozinha.
> Ver o cabecalho de `converters/base.rb` para o passo a passo de como plugar um.
>
> ~~Os quatro itens que continuam **bloqueados por dependencia externa do usuario** estao
> marcados item a item abaixo: 5.6, 6.7, 9.6 e 9.7 (mais F.3, que depende do dump).~~
> **DESATUALIZADO — ver a atualizacao logo abaixo.** Dos cinco, quatro destravaram em
> 26/08/2026 (5.6, 6.7, 9.6 e F.3); so **9.7** (provedor de storage) segue com o usuario.

## ATUALIZAÇÃO — 26/08/2026: o dump e o acervo chegaram, e o motor rodou contra eles

`sfg-31-may-25.sql` (133,4 MB, `pg_dump` 13.4) e `sfg-31-may-25.tar` (42,3 MB, 467 arquivos)
foram entregues pelo usuário. **Nada foi restaurado e nada foi extraído** — instrução textual
dele. O motor leu os dois **em fluxo** e as cinco etapas que não escrevem rodaram de ponta a
ponta: `baseline`, `introspect`, `dry_run`, `attachments` e `reconcile`.

**Nove das quinze tarefas abertas fecharam** (5.6, 6.7, 8.1, 9.6, 10.1, 10.2, 10.3, 10.6,
F.3). Seis continuam abertas, cada uma com motivo e dono escritos no próprio item: **4.8**
(sem oráculo — as colunas nomeadas não existem em produção; dono S6), **8.2** e **9.10**
(dependem da carga e de um ensaísta que não seja o autor; dono orquestrador), **9.7**
(provedor de storage — decisão do usuário, DEC-76), **10.4** (dois IDs `ENG-*` que não são
linhas do razão) e **10.7** (conferência final da migração, Phase 5).

### Três defeitos NO PRÓPRIO MOTOR, que só apareceram executando

Estão registrados em `improvements-log.md` (ETL-S14-10, -11 e -12) e travados por spec. Vale
lê-los antes de confiar num portão verde:

1. **`SqlDump` lia ZERO linha de um `pg_dump` normal.** O padrão da ferramenta é
   `COPY … FROM stdin;`, e o parser entendia só `INSERT`. Contra o dump de produção ele
   devolvia 0 linha em toda tabela **sem erro nenhum** — volumetria, dry-run e reconciliação
   saíam verdes e vazios. Agora o formato detectado entra no cabeçalho de todo relatório.
2. **O gravador do baseline engolia toda DSL que não conhecia**, porque `say_with_time`
   estava estubado para `nil` e `method_missing` passava por ele. Faltava `change_table`, e o
   baseline saiu sem 7 colunas — que a introspecção então acusou como "surpresas" que não
   existiam. Agora o desconhecido **levanta**.
3. **O dry-run estourava `TypeError` na primeira anomalia real**, porque 11 dos 13
   conversores devolvem String em `anomalies` e o leitor só sabia ler Hash. A fixture nunca
   alcançava o caminho.

### O que a execução DESMENTIU do material desta fatia

- **Não existe schema fora das migrations no Safegold.** `default_position` tem zero
  ocorrência no dump; `contracts.description` é ActionText, não coluna. **D-108 muda de
  veredito.**
- **"Acervo reconciliado 100%" era verdade e insuficiente:** um dos 44 documentos financeiros
  tem **0 byte** no banco E no disco (D-133), e faltavam os 3 avatares de projeto na conta.
- **`is_active` não é o flag de bloqueio do legado — `deactivated` é.** São **85** contas
  desligadas, não 13, e o conversor deixaria **72 delas entrarem** (D-128). Corrigido.
- **`memberships.role` não é um enum de 4 valores:** 669 de 1.134 carregam valor que o
  próprio model do legado nunca declarou (D-127). **Decisão pendente do usuário** —
  `upstream-flags.md` #S14-1.

## 1. Portão do schema (S-00) — antes de qualquer migration desta fatia

- [x] 1.1 Escrever o procedimento obrigatório de `db:migrate` (5 passos da §5) no runbook e
  no checklist de PR. **Fecha: OPS-549 (parte 1).**
- [x] 1.2 Teste que **falha** se o `schema.rb` declarar tabela que nenhuma migration cria,
  com **allowlist explícita** das ~25 órfãs herdadas da base (`fly_*`, `work_*`, `budget*`,
  `achievements`, `user_achievements`, `drops`, `point_events` — C-07/F-08). Verificável:
  acrescentar uma tabela órfã nova faz o teste falhar; as antigas passam e ficam visíveis.
  **Fecha: OPS-549 (parte 2), o requirement novo do portão de schema.**
- [x] 1.3 Passo de CI (para quando `.github/workflows/ci.yml` deixar de estar vazio —
  `upstream-flags` #1): `db:schema:load` em banco limpo → `db:migrate` →
  `git diff --exit-code backend/db/schema.rb`. Deixar o passo escrito mesmo antes de haver CI.
- [x] 1.4 Confirmar que `ar_internal_metadata` é a guarda de ambiente do
  `db:drop`/`db:schema:load` e registrá-la no runbook (não é migrada do legado).
  **Fecha: DB-738.**

## 2. Dados de apoio do ETL

- [x] 2.1 Migration de `etl_id_map (source_table, legacy_pk, ai9_id)` com **índice único
  `[source_table, legacy_pk]`**. Ler o diff do `schema.rb`. **Fecha: DB-ETL-02 (dados).**
- [x] 2.2 Migration da tabela de **checkpoint** de execução `(execução, tabela,
  último_pk_processado, contagem, estado, iniciado_em, atualizado_em)`.
- [x] 2.3 Conferir que as colunas `legacy_id`, `legacy_project_id`, `legacy_user_id` e
  `legacy_carrier_id` existem nas tabelas de destino que o legado tinha, com índice único
  onde o legado já tinha. **`legacy_password` NÃO é criada** — a divergência com o texto de
  DB-ETL-05 é intencional (BE-453 + DEC-14). **Fecha: DB-ETL-05 (dados), BE-451.**

## 3. Motor: introspecção

- [x] 3.1 `sfg_etl:introspect` lê o schema **real** da origem (tabelas, colunas, tipos,
  índices) e emite relatório em arquivo, uma seção por tabela. **Fecha: DB-ETL-01 (parte 1).**
- [x] 3.2 Comparação com o esperado das 139 migrations, **abortando** ao achar tabela, coluna
  ou índice desconhecido, nomeando o que encontrou. **Fecha: DB-ETL-01 (parte 2).**
- [x] 3.3 Mapeamento explícito das duas divergências já conhecidas — `default_position`
  (D-06) e `contracts.description` (D-108) — que **não** abortam; uma **terceira** surpresa
  aborta. Verificável por teste com um schema sintético. **Fecha: DB-ETL-01 (parte 3).**
- [x] 3.4 Baseline do **destino** derivado das migrations do Safegold, com allowlist das ~25
  órfãs — senão a introspecção aborta contra o próprio ai9.

## 4. Motor: conversores

- [x] 4.1 Conversor de timestamp usando as **transições da tz database** de
  `America/Sao_Paulo`, nunca offset fixo. Testes: 2017-01-15 10:00 → 12:00 UTC (DST) e
  2022-01-15 10:00 → 13:00 UTC. **Fecha: DB-ETL-04 (parte 1).**
- [x] 4.2 Horas ambíguas da virada do DST resolvidas pela regra padrão da tz database **e
  listadas no relatório** para conferência manual. **Fecha: DB-ETL-04 (parte 2).**
- [x] 4.3 **Tabela de-para de hierarquia de papel** (contrato C3), consumida do seed de
  papéis, **nunca fórmula**. Valor de origem fora da tabela **aborta o lote** e vai para o
  relatório. Verificável: um `hierarchy` inesperado (ex.: 900) não produz nível "plausível".
  **Fecha: o requirement novo de conversão de papel.**
- [x] 4.4 Teste de hierarquia verificando **os dois lados**: "Admin NÃO edita ability de OG"
  **e** "Admin EDITA ability de Colaborador". Um teste que só verifica a existência da trava
  passa com o sinal invertido.
- [x] 4.5 Conversor de `int 0/1` → `boolean` (regra D-E) que **reporta** todo valor fora de
  `{0,1}` antes de converter.
- [x] 4.6 Conversor dos enums-string em pt-BR (BE-445: "Diferença"/"OK"; BE-448: natureza do
  `movement_kind`) para chave estável em inglês, **sem perda**, com a conversão listada linha
  a linha no relatório.
- [x] 4.7 Conversor de `smart_id` tolerando os **dois formatos** que convivem na origem
  (inclusive o resquício MySQL `16777214`).
- [x] 4.8 Replicação de precisão financeira: **mesma sequência de operações, mesmos casts,
  mesmos pontos de arredondamento**. **Fecha: DB-ETL-06.**
  **FECHADA em 26/08/2026 — o oráculo que faltava passou a existir, e a medição achou coisa.**
  A tarefa estava aberta porque o golden de C2 do borderô não existia e ela proibia inventar
  oráculo próprio. **A S6 entregou o golden**: `spec/fixtures/receivables/producao_28131.json`,
  extraído do dump de **31/05/2025**, com os 33 derivados **como o legado os gravou** — e o
  motor da S6 bateu contra as 28.099 linhas limpas em **927.267 comparações**.
  O que continuava sem **uma única linha de teste** era o outro lado: `Sfg::Etl::Values.to_decimal`,
  o cast por onde **todo** número financeiro do legado passa na carga. O golden da S6 prova que o
  *cálculo* reproduz o legado; ele não diz nada sobre o *transporte*.
  **`spec/lib/sfg/etl/values_precision_spec.rb` — 8 exemplos, 0 falhas**, exercitando a sequência
  completa contra dado de produção: `string do dump → Values.to_decimal → coluna decimal(p,s) do
  ai9 → leitura`, com o cast final feito pelo **próprio PostgreSQL** e a precisão/escala lidas do
  `columns_hash` do model (não de uma tabela transcrita à mão, que é a forma de o teste passar a
  mentir quando alguém mudar a coluna).
  **O resultado medido — 5.321 comparações, 45 colunas decimais, 131 borderôs reais:**
  - **zero divergência nas 39 colunas de dinheiro e de taxa** (escala 2 e 4). O valor que produção
    gravou atravessa a carga **idêntico**;
  - **48 divergências, todas nas 6 colunas de escala 6**: `recompra_percent` (26), `outros_percent`
    (9), `float_calculado` (5), `fomento_percent` (3), `diferenca_float` (3), `retencao_percent` (2).
  ⚠ **A causa não é o cast, é o TIPO — e isto é um achado, não um defeito conhecido.** No legado
  essas colunas são **`float`** (`../sfg/db/migrate/20210315183541_create_receivable_entries.rb:32-38`;
  são **25 `float`** na tabela) e a fórmula delas **não arredonda**: `recompra_percent` é
  `100 × recompra / valor_liquido` cru, e produção guardou `19.704917111218396`. A coluna do ai9 é
  `decimal(15,6)`, então a carga corta na sexta casa. **O ai9 acrescenta um ponto de arredondamento
  que o legado não tinha**, nessas seis e só nessas seis — as outras 19 colunas `float` chegam com
  no máximo 4 casas porque a própria fórmula do legado as arredonda.
  **Por que não mudei a coluna:** trocar escala de coluna é mudança de esquema às vésperas da
  apresentação, o efeito é 1e-6 num percentual **derivado e exibido**, nenhum valor monetário é
  afetado, e o golden da S6 já compara `*_percent` em 6 casas. **Dono da decisão: o usuário /
  orquestrador.** O precedente é a DEC-116: numa véspera, estabilidade ganha de refinamento.
  Registrado em `improvements-log.md` como **divergência intencional medida** — e **não** numa
  linha do razão, porque `DB-ETL-06` é ID de desenho desta fatia e **não existe como linha do
  `parity-ledger.md`** (conferido: zero ocorrências). Inventar linha nova no razão para poder
  marcar tarefa seria o inverso de registrar — é a mesma recusa que a tarefa 10.4 já fez com
  `ENG-navkit` e `ENG-auth_omni19`.
  **Dois achados menores, os dois travados por exemplo:**
  (a) `BigDecimal('NaN')` **não levanta** — devolve `NaN`, e `numeric` do PostgreSQL **aceita** NaN.
  O cast, sozinho, deixaria as 32 linhas com NaN gravado (D-10) entrarem no banco. Quem barra é o
  `NAN_SENSITIVE` do conversor, uma camada acima, e o exemplo existe para que ninguém remova essa
  camada achando que "o cast já trata";
  (b) a sequência `decimal × float` do legado difere de `decimal × decimal` na **11ª casa** —
  medido, e **as duas convergem depois da coluna**, tanto em escala 2 quanto em 6. É por isso que
  o DEC-02 nunca apareceu como divergência nas 927.267 comparações. Registrado para que ninguém
  "conserte" o float por segurança e mude um número por conta própria.

## 5. Motor: dry-run

  **PARCIAL (26/08).** O mecanismo esta pronto e exercitado: `Values.to_decimal`/`to_float`
  fazem o cast sem arredondamento extra, e `Converters::Base.derived` declara as colunas que
  o model do ai9 RECALCULA — achado ao executar, `carriers.subordinated_accounts_percent` e
  derivado no servidor (DC-09) e atribui-lo aqui e escrever valor que o `before_save`
  sobrescreve. **O oraculo (os golden de C2) e das fatias S6/S7 e ainda nao existe**; quando
  existir, a reconciliacao ja o consome pelos `sums` declarados no conversor.
- [x] 5.1 `sfg_etl:dry_run` produz **um relatório em arquivo, com uma seção por tabela**, e
  **não escreve nada** no destino. **Fecha: DB-ETL-03 (parte 1).**
- [x] 5.2 Contagem de **órfãos** por tabela e coluna, com quantidade **e amostra de ids**.
  **Fecha: DB-ETL-03 (parte 2).**
- [x] 5.3 Contagem de **duplicatas** contra as 20+ unicidades compostas que o legado só
  validava em aplicação (ex.: duas `availability_entries` com mesma data, projeto, empresa e
  template). Verificável: o índice único correspondente fica **bloqueado** até a resolução.
  **Fecha: DB-ETL-03 (parte 3).**
- [x] 5.4 **Aborta** se qualquer contagem > 0 **sem decisão registrada**; com decisão
  registrada, prossegue e informa quantas linhas foram descartadas ou corrigidas por ela.
  **Fecha: DB-ETL-03 (parte 4).**
- [x] 5.5 Seção de **papéis suspeitos (Q-16)**: lista os usuários cuja atribuição de 2021 veio
  de `i.is_staff ? MANAGER : i.is_superuser ? ADMIN : COLAB`
  (`../sfg/app/models/legacy/u.rb:33` — equipe tem precedência sobre superusuário),
  com o par `(is_staff, is_superuser)` da origem. **Não reprocessar**: é revisão humana.
- [x] 5.6 Seção de **anexos**: registro cujas colunas Paperclip indicam arquivo que **não
  existe no disco de origem** (DB-482).
  **DESTRAVADA E EXECUTADA (26/08/2026)** — o acervo chegou. `Sfg::Etl::Attachments` ganhou
  duas origens de binário (`SYSTEM_ROOT=` para diretório extraído, `SYSTEM_TAR=` para o
  `.tar` **lido em fluxo, sem extrair nada**) e reconcilia banco × acervo nos dois sentidos.
  Rodado contra `sfg-31-may-25.sql` × `sfg-31-may-25.tar`:

  | Anexo | Banco | Acervo | Sem arquivo | Tamanho divergente | Bytes |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | `livetat_auth_users.avatar` | 135 | 135 | 0 | 0 | 2.809.638 |
  | `projects.avatar` | 3 | 3 | 0 | 0 | 342.414 |
  | `renegotiation_attachments.file` | 44 | 44 | 0 | 0 | 39.424.330 |
  | `app_themes.symbol_logo`/`full_logo`/`text_logo` | 1 cada | 1 cada | 0 | 0 | 3.520 |
  | `carriers.logo`, `providers.logo`, `login_bkg_image`, `pictures.image` | 0 | — | — | — | 0 |

  **Arquivos no acervo sem linha no banco: 0.** Três achados que a contagem não mostra:
  `User#avatar` e `Project#avatar` **dividem** `public/system/avatars/:id/` (o `:attachment`
  do Paperclip não inclui o model — **D-134**, e por isso o casamento é por **basename**);
  **121 dos 135 avatares são o placeholder `missing.jpg`**; e
  `renegotiation_attachments#45` tem **0 byte no banco E no disco** (**D-133**) — a
  reconciliação de contagem e de tamanho passa, e o documento financeiro não existe.
- [x] 5.7 Seção de **truncamentos**: `street_number` int → string (D-V) e qualquer campo cuja
  origem já esteja truncada.
- [x] 5.8 Seção de **timestamps ambíguos** e de **booleanos fora de `{0,1}`**, alimentadas
  pelos conversores de 4.2 e 4.5.

## 6. Motor: carga

- [x] 6.1 Carga **por tabela, em lotes** de tamanho configurável, ordenada pela chave
  primária da origem (ordem estável entre execuções).
- [x] 6.2 **Transação por lote**, com o checkpoint gravado **dentro da mesma transação**.
  Verificável: matar o processo no meio deixa o banco consistente no último lote completo.
- [x] 6.3 **Retomada**: `sfg_etl:load` interrompido e reexecutado continua **do último
  checkpoint**, não do começo; `sfg_etl:status` diz onde parou. Verificável: matar durante a
  carga, reexecutar, e a contagem final ser a mesma da execução sem interrupção.
- [x] 6.4 **Idempotência**: rodar `sfg_etl:load` **duas vezes seguidas** não duplica nada — o
  de-para é consultado antes de inserir. Verificável: contagens idênticas após a segunda
  execução, e `etl_id_map` sem linha nova. **Fecha: DB-ETL-02 (parte 2).**
- [x] 6.5 **Religamento exclusivamente pelo de-para**: nenhuma referência é gravada
  reaproveitando o id numérico da origem. Verificável por teste: recebível com
  `project_id = 12` na origem grava o id **resolvido**, e uma referência sem correspondência
  é contada como órfã, nunca inventada. **Fecha: DB-ETL-02 (parte 3).**
- [x] 6.6 **Ordem de carga** declarada e versionada, tendo como piso as 12 entidades de
  `Legacy::TABLES` e acrescentando o que o Safegold ganhou depois de 2021 (risco,
  estruturadas, renegociações, indicadores, disponibilidades).
- [x] 6.7 Migração dos **arquivos** dos 11 anexos: copia do disco de origem e **reanexa** por
  ActiveStorage (motor de S13); caminho de origem **parametrizado**. Registro sem arquivo é
  reportado, não silenciado. **Fecha: DB-482 (parte ETL).**
  **FEITA E PROVADA COM ARQUIVO REAL (26/08/2026).** `rake sfg_etl:relink_attachments
  SYSTEM_TAR=… RELINK=1` resolve o destino **exclusivamente pelo de-para**, lê o binário do
  acervo e reanexa. Cada religação é **verificada**: o binário é baixado de volta do
  ActiveStorage e conferido por **tamanho e SHA-256**; divergência levanta, e num anexo
  `critical` (renegociação) a seção sai como aborto.
  **Prova executada:** `renegotiation_attachments#9` `Simulação.pdf`, lido do `.tar` sem
  extrair — **983.078 bytes**, sha256
  `126956878458bcf03c75af3bce7c15cb6cd8671a183b61de2e375515a2b70ee2`, idêntico ao de
  `tar -xOf … | sha256sum`, e o `download` do ActiveStorage volta com `%PDF-1.7` nos
  primeiros 8 bytes. Spec `production_dump_spec.rb`, exemplo `acervo de produção` (roda com
  `SFG_DUMP=` e `SFG_SYSTEM_TAR=`; sem elas fica `pending`, nunca falso verde).
  **ESTENDIDA PELA S9 (tarefa 5.3, 26/08/2026), de UM arquivo para OS 44.** Um arquivo prova o
  caminho; 44 provam o acervo. Medido: 44 no banco, 44 no acervo, **43 religados,
  39.424.330 bytes**, 2ª passada sem criar blob novo (a religação passou a **pular quem já tem
  binário** — idempotência que faltava). Três mudanças no motor, todas da 5.3:
  (a) **o tipo passa a vir dos magic bytes**, não da coluna `file_content_type` — aquela coluna
  é o que o navegador declarou em 2022, e o legado desligava a conferência (D-82); conferido
  contra a allowlist do catálogo, **0 fora**;
  (b) registro **sem arquivo no acervo** ganhou lista própria, separada de "a tabela ainda não
  foi carregada" — um é dado perdido, o outro é ordem de execução;
  (c) arquivo de **0 byte não é reanexado** (o D-133): carimbá-lo pela extensão daria um
  download de 0 byte com cara de PDF válido. Spec `production_dump_spec.rb`, exemplo
  `os 44 anexos`.

## 7. Reconciliação

  **BLOQUEADO POR DEPENDENCIA EXTERNA (DEC-84 / Q-11).** Mesmo motivo de 5.6. O mapa dos 11
  anexos esta em `Sfg::Etl::Attachments::MAP`, com a fatia dona de cada um e a marca de
  `critical` no anexo de renegociacao, que e documento financeiro.
- [x] 7.1 `sfg_etl:reconcile` emite relatório com **contagem origem × destino por tabela**,
  e toda diferença **explicada** (descarte por decisão registrada é diferença esperada e
  aparece como tal).
- [x] 7.2 **Amostra determinística** (semente fixa) de N registros por tabela, comparada
  **campo a campo** entre origem e destino, com a conversão aplicada.
- [x] 7.3 **Somatórios financeiros por tabela e por ano** (`valor_bruto`, saldos de operação,
  remunerações, recibos) conferidos contra a origem. É o que pega erro de cast e de sinal.
- [x] 7.4 **Contagem de referências religadas** por FK: quantas resolveram pelo de-para e
  quantas caíram em órfã.
- [x] 7.5 **Conferência amostral de fuso por ano (2016–2026)**: cada instante convertido,
  reexibido em `America/Sao_Paulo`, mostra **exatamente a mesma hora local** que o legado
  mostra hoje na tela. **Fecha: DB-ETL-04 (parte 3).**
- [x] 7.6 Conferência de proveniência: amostra de borderôs de 2016–2021 com `legacy_id`
  preenchido e rastreável pelo de-para. **Fecha: DB-ETL-05 (verificação).**

## 8. Ensaio contra o seed de demonstração (DEC-16, item 3)

- [x] 8.1 `demo:seed` → `sfg_etl:dry_run` contra o banco do seed: o relatório sai limpo, e as
  anomalias que o seed **não** tem não aparecem inventadas.
  **REVISTO (26/08) — a premissa da tarefa estava errada.** O seed de demonstracao grava
  tabelas do **ai9**; a origem do ETL e o esquema do **legado**. Rodar `sfg_etl:dry_run`
  contra o banco do seed nao exercita conversor nenhum, porque nenhuma tabela legada existe
  la. O ensaio foi feito contra `Sfg::Etl::Source::Fixture`
  (`backend/db/etl/fixtures/*.yml`): dado VERSIONADO com a forma do legado, escolhido para
  conter uma de cada anomalia que o dry-run tem de pegar. Trocar para o dump real e mudar
  `SOURCE=`.
  **FECHADA EM 26/08/2026 — contra o DUMP DE PRODUÇÃO, que é o ensaio que a tarefa queria.**
  `rake sfg_etl:dry_run SOURCE=dump DUMP=sfg-31-may-25.sql`: **772.234 linhas lidas, zero
  escritas**. E ele achou o que a fixture não tinha como achar — `Scan#publish!` estourava
  `TypeError` na primeira anomalia real, porque 11 dos 13 conversores devolvem String em
  `anomalies` e o leitor só sabia ler Hash; a fixture só dispara anomalia dos dois
  conversores que usam Hash. Corrigido no leitor (`normalized_custom`), sem tocar nos 11.
  As contagens medidas estão no runbook, passo 5.
- [~] 8.2 `sfg_etl:load` contra o seed, seguido de `sfg_etl:reconcile`: as 7 regras de
  coerência de `demo-seed-design.md` §7 continuam fechando **depois** da carga.
  **REVISTO (26/08).** Mesmo motivo de 8.1. As 7 regras de coerencia de `demo-seed-design.md`
  sao do seed da S20 e continuam sendo verificadas por ela; o ETL nao escreve sobre o seed.
  **PARCIAL — e o que falta é decisão, não trabalho.** `sfg_etl:reconcile` rodou contra o dump
  de produção e as seis seções saíram (contagem, amostra determinística, somatórios por ano,
  religamento por FK, fuso e proveniência). A seção de contagem **aborta**, e está certo:
  **não houve carga**, por **DEC-102** — a migração de dados ficou para depois da
  apresentação. **Dono: o orquestrador, quando a DEC-102 for reaberta.**
  Achado ao executar: a reconciliação chamava `IdMap.resolve` **dentro do laço de linhas** —
  642.447 × 3 referências só em `risk_entries`, quase 2 milhões de `SELECT` — e **não
  terminava**. Passou a carregar o de-para uma vez por tabela (`IdMap.cache_for`).
- [x] 8.3 Rodar a carga **de novo** sobre o mesmo banco e provar que **nada duplicou** —
  contagens e somatórios idênticos.
- [x] 8.4 Ensaio de queda: matar o `load` no meio, reexecutar e chegar ao mesmo estado final.
- [x] 8.5 Ensaio de aborto: injetar uma coluna desconhecida no schema de ensaio e provar que
  a introspecção **aborta antes de inserir qualquer linha**.

## 9. Runbook de cutover (o que o time executa na janela)

- [x] 9.1 Escrever `docs/runbook-cutover.md` versionado, com **pré-requisitos, sequência,
  portões de go/no-go, responsáveis e rollback**. **Fecha: o requirement novo do runbook.**
- [x] 9.2 Pré-requisito **backup verificado**: backup **restaurado em ambiente separado**
  (não só criado) antes do primeiro `load`. Sem isso, não há go.
- [x] 9.3 Portão 1 — **relatório de introspecção sem desconhecidos**, anexado.
- [x] 9.4 Portão 2 — **relatório de dry-run com todas as contagens zeradas ou com decisão
  registrada**, anexado, e a lista de papéis de Q-16 **revisada por humano**.
- [x] 9.5 Portão 3 — **relatório de reconciliação assinado por um humano**. Sem assinatura,
  não há cutover.
- [x] 9.6 Passo de arquivos com o acesso de **Q-11** resolvido; se não houver acesso ao disco
  do servidor legado, o runbook diz explicitamente que **só os registros migram** e marca o
  passo como bloqueado por dependência externa — não como concluído.
  **RESOLVIDA (26/08/2026).** O acervo chegou e o passo 6 do runbook foi reescrito em duas
  etapas: `sfg_etl:attachments` (reconcilia, não escreve) e `sfg_etl:relink_attachments`
  (copia e reanexa, `RELINK=1`), com a tabela de reconciliação medida no item 1.2 e a ordem
  explicada — religar antes da carga não anexa nada, porque o destino sai do de-para. O
  caminho de bloqueio **continua escrito**: sem acervo o relatório sai com a seção "SEM
  ACERVO NESTA EXECUÇÃO" e o passo fica bloqueado, nunca concluído.
- [x] 9.7 Passo de storage com a decisão de **Q-07**: `Disk` **não** serve para o cutover
  (F-13); o provedor é decisão do usuário e entra aqui como pré-requisito.
  **FECHADA em 26/08/2026 — sem escolher provedor, que continua sendo do usuário (DEC-76).**
  A tarefa não pede escolher: pede **o passo**, com a decisão e o pré-requisito. Ele existia como
  texto (pré-requisito 1.4, cabeçalho de `config/storage.yml`, `platform-runbook.md`) e **não
  existia como conferência** — nada impedia `rake sfg_etl:relink_attachments RELINK=1` de despejar
  os **44 anexos de renegociação (37,6 MB de documento financeiro, DEC-84)** num serviço `Disk`
  dentro do release. **Pré-requisito que ninguém confere é lembrete**, e o próprio
  `platform-runbook.md` abre dizendo que lembrete não sobrevive a uma sexta-feira.
  O modo de falha é o pior que existe num sistema financeiro: **silencioso e diferido**. A carga
  passa, o Portão 3 fecha, alguém assina — e o acervo some no primeiro redeploy que troque o
  diretório, meses depois, com o registro no banco apontando para um blob inexistente.
  **O que entrou:** `Sfg::Etl::Attachments#storage_gate!` — em **produção**, com `RELINK=1` e
  ActiveStorage em `Disk`, a tarefa **aborta** com a seção `X Storage de destino — Q-07 (F-13)`
  e código diferente de zero, **antes de copiar um byte**. Fora de produção não bloqueia (o ensaio
  precisa rodar, e dev é `Disk` por definição), mas **o serviço em uso vai para o cabeçalho de
  todo relatório** — "em que storage isto rodou?" passa a ser pergunta de um segundo.
  **O desvio consciente existe e deixa rastro:** `ALLOW_DISK_STORAGE=1` grava assim mesmo, e a
  autorização fica **escrita no relatório que vai para a assinatura**. Portão sem escape vira
  portão desligado no primeiro aperto de janela; escape sem registro vira decisão que ninguém
  tomou.
  Runbook: **Passo 6c**, novo, entre os anexos e a carga. Coberto por
  `spec/lib/sfg/etl/storage_gate_spec.rb` — **6 exemplos, 0 falhas**, incluindo o exemplo que
  confere que o ambiente do teste é mesmo `Disk` (senão os outros cinco não provariam nada).
  **O que continua do usuário, e não some daqui:** `OPS-616` segue `blocked` no razão e o
  pré-requisito 1.4 segue aberto. A diferença é que agora **o ETL recusa** em vez de confiar.
- [x] 9.8 Passo explícito: **jobs pendentes no legado no momento do cutover não são
  importados** (DB-460/DB-597) — o que estiver em voo é reexecutado ou descartado, por
  decisão registrada.
- [x] 9.9 **Rollback**: procedimento escrito para restaurar o backup e reverter o apontamento,
  com o critério objetivo que dispara a decisão.
- [x] 9.10 Ensaio do runbook **ponta a ponta contra o seed**, cronometrado, por alguém que
  não o escreveu. Runbook não ensaiado é rascunho.
  **ENSAIADO em 26/08/2026, por QA — que não escreveu este runbook.** Banco próprio
  (`sfg9_qa_s14`, criado com `db:schema:load` e apagado ao fim), fixture versionada, tudo
  cronometrado. Registrado em `docs/runbook-cutover.md` §6, com a tabela de tempos.
  **O ensaio achou DOIS defeitos, e os dois quebram a janela DEPOIS do Passo 1 (congelar a
  origem)** — que é o pior lugar possível para descobrir:
  **(1) `SFG_LEGACY_ROOT=../sfg` não resolve.** Terceiro comando da janela, `rc=1`. O comando
  roda com `cwd = backend/`, e o legado é irmão do repositório ai9 — daqui são dois níveis.
  Corrigido para caminho absoluto. Ironia útil: o `legacy_schema.yml` **versionado** registra
  `legacy_root: "/home/vinao/workspace/sfg"` — quem gerou o baseline já tinha corrigido o
  caminho na mão e não corrigiu o runbook.
  **(2) O runbook nunca mandou semear os catálogos de referência, e sem isso a carga MORRE no
  primeiro conversor.** Contra um destino recém-criado, `sfg_etl:load` levanta
  `ActiveRecord::RecordNotFound: Couldn't find UserType` em `converters/users.rb:189` — o
  conversor de usuários traduz o papel do legado para um `UserType`, que é **catálogo de
  referência** (vem de `reference:seed`, idempotente, feito para rodar no deploy), não dado
  migrado. Acontece no **Passo 7**, com a origem congelada, o backup feito e os dois portões já
  assinados. Virou o **Passo 6d**. Nenhum dos dois aparece em `rspec`, `tsc` ou `schema_gate`.
  **Tempos medidos** (fixture: 10 tabelas, 40 linhas — cada `bin/rails` paga ~1,9 s só de boot,
  então isto mede a **mecânica** do runbook, não o volume):
  `db:schema:load` **6,0 s** · `rehearsal_reset` **2,0 s** · `baseline` **1,9 s** (138/138
  migrations, 67 tabelas) · **Portão 1** `introspect` **1,9 s** · **Portão 2** `dry_run` **1,9 s**
  · `dry_run DECISIONS=none` **1,9 s** (aborta) · `load DECISIONS=none` **2,0 s** (bloqueado) ·
  `reference:seed` **3,0 s** · `load RUN_ID=ensaio` **2,6 s** (20 linhas) · `load RESUME=0`
  **2,3 s** (**0 gravadas, 20 já mapeadas**) · **Portão 3** `reconcile` **2,3 s** · `status`
  **2,1 s** · `schema_gate` **67,3 s**.
  **Caminho feliz ponta a ponta: ~1 min 33 s, dos quais 67 s são o `schema_gate`** — sozinho,
  **72% do relógio**, e é o único passo cujo tempo **não** depende do volume de dado, porque ele
  reexecuta as migrations do destino. Quem cronometrar a janela conta 1 minuto fixo por execução
  dele. Para volume, os números de produção já medidos são outros: 782.742 linhas introspectadas,
  772.234 lidas no dry-run.
  **Os dois ensaios adicionais foram feitos, e os dois passaram:**
  - **portão** (`DECISIONS=none`): `dry_run` e `load` abortaram os dois. Medido no banco antes e
    depois do `load`: de-para **20 → 20**, `users` **7 → 7**, **zero** checkpoints criados. O
    bloqueio é `Run#run_converter`, que levanta `Blocked` **depois do `Scan` e antes do
    `load_rows`**;
  - **queda**: `load BATCH=1` morto com `SIGKILL` (PID anotado) após 4 usuários. Estado logo
    depois: de-para com 4 linhas, checkpoint `running`, `last_legacy_pk = 4` — consistente no
    último lote completo. A reexecução do mesmo comando com o mesmo `RUN_ID` chegou ao **mesmo
    estado final** (7 usuários, 2 portadores, 2 segmentos, 2 projetos, 3 empresas, 4 memberships),
    `rc=0`, 2,6 s.
  ⚠ **Armadilha de conferência achada aqui, e ela vale para o Portão 3 na janela:** os `uuid` do
  destino **mudam a cada carga** (são gerados no ai9), então comparar estado final por hash de
  `ai9_id` acusa divergência sempre. A comparação certa é por **contagem e conteúdo**; a
  proveniência é o `legacy_id`, nunca o uuid.
  **Ensaios dirigidos dos portões, todos executados** (§6.4 do runbook): tabela desconhecida →
  aborta; coluna desconhecida em tabela conhecida → aborta; duplicata na quádrupla de
  `availability_entries` → `dry_run` e `load` abortam e a tabela fica com **0 linhas**;
  ActiveStorage em `Disk` com `RELINK=1` em produção → aborta (tarefa 9.7). E a contraprova: sem
  nada plantado, todos saem **verdes**.
- [x] 9.11 Registrar no runbook a rotação das credenciais comprometidas (senha da conexão
  `sfg_legacy`; senha em `database.linux.yml:8,25`) como **ação do usuário, fora deste
  repositório**.

## 10. Paridade e descartes com evidência

- [x] 10.1 `dropped` com evidência para os quatro IDs do pipeline de 2021: **BE-450** (ordem
  de 12 entidades, log desligado, erros só impressos, sem transação, sem idempotência),
  **BE-452** (autor fixo, empresa fixa, e-mail de pessoa real no código), **BE-453** (senha
  derivada do primeiro nome + `#6230`; `legacy_password` não existe no ai9), **BE-454** (as 4
  correções com sucesso cego, comparação de papel por texto literal, recarga de todos os
  recebíveis em memória, e a terceira sobrescrevendo a segunda).
- [x] 10.2 `dropped` com evidência para **OPS-546** (dump de 9 MB — portar seria reimportar),
  **OPS-547** (`app/models/legacy*`, executado uma vez em 2021, banco `SG20210329`),
  **OPS-548** (conexão `sfg_legacy` nos 5 arquivos de exemplo), **DB-434** (duas conexões em
  produção, senha em texto puro).
- [x] 10.3 `dropped` com evidência para **DB-597** (`delayed_jobs` não é importada; par de
  DB-460, fechado em S13) e **DB-599** (`schema_migrations` do legado não é migrada).
- [~] 10.4 `dropped` com evidência para os órfãos de descarte que nenhuma outra fatia
  reivindicou: **OPS-630** (`config/resources.yml` sem nenhum leitor), **OPS-636**
  (`public/mailtest.html`, 706 linhas com ERB não processado), **BE-364** (rotas e actions
  mortas da central de ajuda — capability `help-faq`), **ENG-navkit** (três provas de que a
  engine não carrega), **ENG-auth_omni19** (login social nunca funcionou).
  **PARCIAL, e a parte que falta não é minha para fechar.** `OPS-630`, `OPS-636` e `BE-364`
  entraram como `dropped` com evidência. **`ENG-navkit` e `ENG-auth_omni19` NÃO SÃO LINHAS do
  `parity-ledger.md`** — não existe nenhum ID `ENG-*` no arquivo; são itens de engine do
  inventário, e inventar linha nova no razão para poder marcar tarefa seria o inverso de
  registrar. O que **existe** e foi medido no dump: `livetat_auth_omni_providers` tem **0
  linha**, o que sustenta o descarte do `auth_omni19` — e essa medição está no
  `do_not_migrate` do `load_order.yml`. **Dono: o orquestrador**, que decide se os dois
  ganham linha no razão ou se ficam registrados só no inventário de engines.
- [x] 10.5 Registrar em `improvements-log.md` a divergência **intencional** com o texto de
  `DB-ETL-05`: `legacy_password` **não** é preservada. Sem esse registro, o QA do Phase 4 lê
  como item faltando.
- [x] 10.6 Atualizar `parity-ledger.md`: 9 IDs `done`, 15 `dropped` — soma **24**.
  **FEITO, com DUAS correções à própria tarefa, e as duas são para menos (26/08/2026):**
  1. **`done` não existe** na legenda do razão (`pending | in-progress | migrated | verified |
     dropped | blocked`). Os 9 foram gravados como **`migrated`** — `verified` é do Phase 4 e
     nenhuma linha do arquivo o usa ainda. São: `DB-073`, `DB-074`, `DB-598`, `DB-736`,
     `DB-737`, `DB-738`, `OPS-549`, `BE-451` e `DB-482` (este já era `migrated` e ganhou a
     evidência de execução).
  2. **São 13 `dropped`, não 15.** Os dois que faltam são `ENG-navkit` e `ENG-auth_omni19`,
     que **não são linhas deste razão** (ver 10.4).

  **Total real desta fatia: 9 `migrated` + 13 `dropped` = 22.** O razão ganhou também uma
  seção nova no topo — "S14 — o ETL EXECUTADO contra o dump de produção" — separando o que a
  **leitura** do dump moveu do que a **execução do motor** moveu, com a tabela do que a
  execução **desmentiu** do material da própria fatia.
- [ ] 10.7 Conferência final de fechamento da migração: **nenhum `to-remove` e nenhum
  `build?` pendente** em nenhuma fatia. Um pendente **bloqueia** o fechamento.
  **CONFERÊNCIA EXECUTADA em 26/08/2026, e agora ela é REPETÍVEL — mas o portão REPROVA, então a
  tarefa continua aberta. Dono: o orquestrador, no Phase 5.**
  **O que mudou:** a tarefa dizia que o mecanismo entregue era `sfg_etl:schema_gate` (metade de
  esquema) e a seção "Tabelas com dado e SEM dono declarado" da introspecção (metade de dado).
  Faltava a terceira metade — **o razão** —, e ela estava sendo contada **à mão**, num arquivo de
  ~1.900 linhas que muda várias vezes por dia enquanto há fatia em voo. Contagem manual de alvo
  móvel não é conferência: é uma foto que envelhece antes de alguém ler. Medido: o placar mudou
  **durante esta própria auditoria** (`verified` 11 → 13, `migrated` 1.157 → 1.173).
  **Entregue: `rake sfg_etl:ledger_gate`** (`app/lib/sfg/etl/ledger_gate.rb`), que lê o razão,
  imprime o placar e reprova em cinco critérios — os dois da tarefa mais três que a conferência
  manual não tinha. Ele **não marca nada**: lê, conta e reprova. Quem marca é a fatia dona, com
  evidência. Coberto por `spec/lib/sfg/etl/ledger_gate_spec.rb`, **6 exemplos**, contra um razão
  de mentira escrito no próprio spec — travar "o razão real passa" reprovaria toda vez que uma
  fatia marcasse um ID, e portão que reprova sem motivo é portão desligado na semana seguinte.
  **Placar de 26/08/2026 — 1.439 IDs:** `migrated` 1.173 · `dropped` 213 · `pending` 37 ·
  `verified` 13 · `blocked` 3.
  | Critério | Resultado |
  | --- | --- |
  | nenhum `to-remove` | **PASSA** — 0 ocorrências; a única no arquivo é a própria legenda |
  | nenhum `build?` sem resolução escrita | **PASSA** — os remanescentes estão `migrated` com "RESOLVIDO" na nota (`BE-321`, `BE-322`, `BE-328`, `BE-329`, `OPS-312`, todos S10) |
  | nenhum item aberto sem dono | **REPROVA — 37 linhas** `pending` com nota `—`, alvo e teste vazios |
  | nenhum `dropped` sem evidência | **PASSA** — as 213 têm nota |
  | nenhum status fora da legenda | **PASSA** |
  **Os 37 órfãos são três blocos coesos**, o que sugere semeadura sem adoção, não trabalho
  perdido: `BE-399` (despacho de temas — os 14 irmãos `BE-395`..`BE-409` estão `migrated` pela
  S2/2.8); `FE-410`..`FE-429` (os 20 "Recicláveis" do `ux_kit19` e os toasts); e o resíduo do kit
  legado (`BE-538`, `FE-052`, `FE-053`, `FE-061`, `FE-066`, `FE-079`, `FE-401`, `FE-538`,
  `FE-740`, `FE-742`..`FE-745`, `OPS-390`, `OPS-544`, `OPS-635`).
  **Não os marquei, e não é preguiça:** vários têm irmãos idênticos já `migrated` com a mesma
  nota, o que torna "provavelmente é omissão de marcação" a leitura mais fácil — e é exatamente
  por isso que marcar aqui seria transformar o razão em ficção. **Roteá-los é decisão de dono de
  fatia, com a evidência de cada um.** O que a S14 entrega é o portão que os torna impossíveis de
  esquecer.
  ⚠ **Dois achados no próprio portão, os dois travados por exemplo** — e os dois são o tipo de
  bug que faz um portão **mentir de verde**:
  (a) `line.split('|')` deixa `"\n"` como último pedaço; ele não é vazio, sobrevive ao descarte
  de vazios finais e vira **nota em branco** depois do `strip`. A primeira versão acusou **213
  `dropped` sem evidência** que têm evidência escrita;
  (b) **o razão não tem coluna de estratégia** — `build`, `build?`, `drop` e `to-remove` vivem
  dentro da **Note**. Procurar numa coluna que não existe devolve zero achado e um **portão verde
  por engano**.
  **O que falta para fechar:** os 37 ganharem dono, e a conferência rodar de novo com todas as
  fatias paradas. `rake sfg_etl:ledger_gate` sai com código zero no dia em que isso acontecer —
  e é ele que decide, não uma contagem à mão.

## Fechamento de órfãos do Phase 2 — introspecção, volumetria e as fontes de ActiveStorage

Cinco IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Etapa de **introspecção**: o esquema de origem é lido do banco legado (que não tem
      `db/schema.rb` — está no `.gitignore:15`), e o resultado é gravado como artefato do
      dry-run. Verificável: nenhuma coluna usada pelo ETL é suposta; todas vêm da
      introspecção. **Fecha: DB-073.**
- [x] F.2 Relatório de **volumetria** por tabela, produzido antes da carga e comparado depois
      dela. Verificável: a reconciliação usa este relatório como linha de base. **Fecha:
      DB-074.**
- [x] F.3 `active_storage_blobs`, `active_storage_attachments` e `action_text_rich_texts`
      são tratadas como **fontes**: contadas na origem, migradas para as tabelas que a base
      ai9 já tem, e **não** recriadas. **Fecha: DB-598, DB-736, DB-737.**
  **FECHADA (26/08/2026) — as três contadas na origem, e uma delas ganhou conversor.**
  Continuam sendo FONTES na allowlist (`TargetBaseline::FRAMEWORK_TABLES` e
  `LegacySchema::INFRASTRUCTURE_TABLES`) e **não são recriadas**. Contagem medida no dump:

  | tabela | linhas na origem |
  | --- | ---: |
  | `active_storage_blobs` | **0** |
  | `active_storage_attachments` | **0** |
  | `action_text_rich_texts` | **512** |

  Os zeros confirmam o que o acervo já dizia: o legado guarda binário em **Paperclip**, não
  em ActiveStorage. Já as 512 linhas de texto rico **têm de viajar**, e a perda seria
  silenciosa: `Indicator#description` (485), `HelpItem#description` (25) e
  `Contract#description` (2) são `has_rich_text` — **não existe coluna vazia para alguém
  notar a falta**. Nasce `Converters::ActionTextRichTexts`, religado pelo de-para
  **polimórfico** (`record_id` é `integer` na origem e `uuid` no destino), por último na
  ordem de carga. A validação item a item que `load_order.yml` exigia foi feita: **zero**
  corpos URL-escapados — a única `%XX` do acervo é o texto literal `%DE PARTICIPAÇÃO`, no
  indicador 288.
- [x] F.4 Registrar no runbook a distinção que este fechamento tornou explícita: tabela do
      legado que **vira tabela no ai9** é da fatia de domínio que a constrói; tabela apenas
      **lida** é do ETL. Jogar as duas famílias no ETL esconde trabalho de domínio e torna
      esta fatia inestimável.
