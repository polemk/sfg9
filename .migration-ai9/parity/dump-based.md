# Paridade contra o dump de produção — os itens que esperavam "a carga"

> **26/08/2026.** Fecha a premissa que a DEC-121 e a DEC-124 derrubaram: *"o dump ainda
> não foi carregado; paridade numérica fica `migrated` com o motivo escrito"*. **O dump
> É a carga real, e não virá outro.** Tudo que estava parado esperando a carga foi
> exercitado aqui.

Origem: `sfg_legacy_dump` (localhost, somente leitura) — **56 tabelas, 782.742 linhas**,
retrato de **31/05/2025**. Acervo de binários: `sfg-31-may-25.tar`.
Destino do ensaio: banco próprio `sfg9_dumppar`, criado por `db:schema:load` + `rake
reference:seed`, e um `sfg9_par_test` para a suíte. Nada de dado real foi commitado
(DEC-123); nesta página só há **contagem, somatório e id**.

---

## 1. O escopo, contado aqui e não herdado

**88 IDs.** O briefing estimava "≈90 + 64"; a contagem própria, pela regra escrita
(linha `migrated` cujo motivo cite **carga**, **dump**, **dado real**, **volumetria** ou
**esquema/schema**), dá:

| Como o motivo está escrito | IDs |
| --- | ---: |
| Carimbo **(M6)** — *"schema: prova é a migration + o spec; paridade de dado depende da carga"* | 46 |
| Carimbo **(M1)** — *"paridade NUMÉRICA depende da CARGA do dump (DEC-102)"* | 6 |
| Motivo em prosa na própria linha citando dump/volumetria/esquema | 21 |
| **Motivo que NÃO está na linha** — carimbo terso `S6 (26/08/2026)`, com a razão só no bloco de prosa (*"Depende da carga rodada contra o destino"*) | 18 |
| **Total (união, sem repetição)** | **88** |

Ficaram **fora** 9 linhas que a busca por palavra pega e o critério não: `carga da
classe` (família `Feedback19`, DB-393/394/509/510/595/732, OPS-507/542) e `carga
explícita de definições de marca` (OPS-603). São a palavra "carga" em outro sentido.

**Resultado: 67 promovidos a `verified`, 21 continuam `migrated`** — todos com o motivo
NOVO, medido nesta passada, e nenhum deles repetindo "espera a carga".

---

## 2. A régua

**Verificar executando.** Nenhuma linha subiu por leitura de código nem por portão verde.
Cada uma abaixo carrega **o comando que a provou**. Os comandos, na íntegra:

```bash
# ambiente do ensaio (banco próprio, criado e destruído)
export DATABASE_URL="postgres://sfg9_user:***@localhost/sfg9_dumppar"
export SFG_LEGACY_URL="postgres://sfg9_user:***@localhost/sfg_legacy_dump"

bundle exec rake db:create db:schema:load
bundle exec rake reference:seed
bundle exec rake sfg_etl:introspect  SOURCE=db
bundle exec rake sfg_etl:dry_run     SOURCE=db
bundle exec rake sfg_etl:load        SOURCE=db RUN_ID=dumppar BATCH=2000
bundle exec rake sfg_etl:schema_gate
bundle exec rake sfg_etl:renegotiation_parity SOURCE=db
bundle exec rake sfg_etl:renegotiation_fixups            # ensaio, não grava
bundle exec rake sfg_etl:attachments SYSTEM_TAR=…/sfg-31-may-25.tar
SFG_DUMP=…/sfg-31-may-25.sql SFG_SYSTEM_TAR=…/sfg-31-may-25.tar \
  bundle exec rspec spec/lib/sfg/etl
psql -d sfg9_dumppar   # esquema do DESTINO real (índices, FKs, CHECKs, tipos)
psql -d sfg_legacy_dump # dado da ORIGEM real (duplicatas, órfãos, volumetria)
```

O que cada um mediu:

| Prova | Medição |
| --- | --- |
| `introspect SOURCE=db` | **56 tabelas · 870 linhas de esquema · 782.742 linhas · 0 surpresas** |
| `dry_run SOURCE=db` | 7 órfãos · 4 famílias de duplicata · 2 bloqueios declarados |
| `load SOURCE=db` (executado por partes) | **users 135 · carriers 328 · segments 3 · sub_segments 20 · receivable_kinds 7 · wallets 12 · movement_kinds 18 · resource_sources 6 · projects 83 · companies 112 · memberships 1.134 · project_to_carrier_connections 1.177 · indicators 529 · project_indicator_connections 590 · indicator_entries 6.174 · risk_controls 600 · risk_entries 642.447** — **17 conversores, `lidas = gravadas` em todos**, zero perda. **679.283 linhas reais de produção** entraram no esquema do ai9 |
| `schema_gate` | **PORTÃO VERDE**; 30 órfãs herdadas na allowlist nominal |
| `renegotiation_parity SOURCE=db` | **47.170 comparações · 47.162 iguais · 0 regressões · 8 mudanças declaradas (D-45)** |
| `renegotiation_fixups` (ensaio) | **0** empresa faltando, **0** ordinal fora, **0** renegociação divergente, **0** contador fora do real |
| `attachments SYSTEM_TAR` | **135 avatares de usuário** no banco × 135 no acervo · **3 avatares de projeto** × 3 · **44 anexos** de renegociação · **39.424.330 bytes** conferidos byte a byte · **0 arquivo no acervo sem linha no banco** |
| `rspec spec/lib/sfg/etl` com `SFG_DUMP` e `SFG_SYSTEM_TAR` | **32 exemplos, 0 falhas** — os 3 que ficavam `pending` por falta de artefato **rodaram** |
| `rspec spec/lib/sfg/etl` sem os artefatos | 148 exemplos, 0 falhas |

---

## 3. Cinco defeitos, e quatro deles param a virada

Todos foram achados **executando a carga real**, e nenhum deles apareceria contra o seed.

### D-PAR-01 — um CEP de 7 dígitos derrubava a carga inteira · **CORRIGIDO**

`rake sfg_etl:load SOURCE=db` morria em `projects` com
`ActiveRecord::RecordInvalid: Cep deve ter 8 dígitos` — **exceção não tratada**,
backtrace no terminal, **nenhuma linha de relatório**, execução parada no meio do lote.

Medido: **3 projetos de 83** com CEP de 7 dígitos (60 vazios, 20 com 8).
`../sfg` não validava CEP; `Project` do ai9 valida (`app/models/project.rb:95`) e o
escritor do ETL chama `save!`.

**Reproduzir:** `psql -d sfg_legacy_dump -c "select length(regexp_replace(coalesce(cep,''),'[^0-9]','','g')), count(*) from projects group by 1"` → `0|60  7|3  8|20`.

**Conserto** (commit `36cbb7c9`): `Sfg::Etl::Converters::Projects.usable_cep` — CEP fora
de 8 dígitos entra **vazio** e sai como anomalia declarada `projects:cep_invalido`. A
carga passa a **parar num relatório**, não num backtrace. A disposição final é do
usuário: a entrada em `db/etl/decisions.yml` **não foi escrita**, de propósito.
Depois do conserto: `projects 83 lidas · 83 gravadas`, 63 sem CEP e 20 com.

### D-PAR-02 — 32 borderôs de produção com `NaN` **impedem a carga**. Bloqueador de cutover

`rake sfg_etl:load` morre em `receivable_entries` com:

> `ActiveRecord::RecordInvalid: Valor infinito ou indeterminado em: recompra_percent,
> total_deducoes, vlr_liq_recebido, recompra. O borderô não pode ser gravado assim.`

Medido na origem: **1 tarifa com `NaN`** (1 borderô), e **32 borderôs** que **já têm
`NaN` gravado nos derivados** — ids `18097, 19383, 19504, 19542, 19665, 19797, 19947,
20155, 20163, 20564, 20566, 20700, 21231, 21470, 21678, 21999, 22424, 22440, 22524,
22591, 22594, 22618, 22650, 22679, 22723, 22772, 23656, 23677, 24451, 27164, 27806,
28443`.

Isto **confirma executando** o que o `D-QA4-03` tinha dito lendo, e vai além dele: a
decisão do usuário (*"tarifa com `NaN` entra como NULO, e as somas ignoram"`) **está
assinada** em `db/etl/decisions.yml` (`custom:receivable_taxes`, `signed_by: usuário`) e
**não está no código**. Mas mesmo implementada, ela resolve **1** linha — os outros **32
borderôs carregam `NaN` nas colunas derivadas do próprio borderô**, e o `ReceivableEntry`
do ai9 recusa gravá-los. Sem disposição para esses 32, `receivable_entries`,
`receivable_taxes` e tudo que depende deles **não migram**.

**Reproduzir:** `psql -d sfg_legacy_dump -c "select count(*) from receivable_entries where recompra::text='NaN' or recompra_percent::text='NaN' or total_deducoes::text='NaN' or vlr_liq_recebido::text='NaN'"` → `32`.

**Dono: usuário.** É decisão de negócio (carregar com zero? com nulo? recalcular? deixar
fora e listar?), não conserto de código.

> **Re-executado às 00:07 de 27/08, depois do commit `772f7495`** (*"DEC-120 no código:
> tarifa com `NaN` entra como NULO"*, de outro agente, que fecha o `D-QA4-03`): o `load`
> de `receivable_entries` **continua morrendo na mesma mensagem**. Confirma que são
> **dois** problemas, e que só o primeiro está resolvido: a tarifa com `NaN` (1 linha) e
> os **32 borderôs que já vieram com `NaN` gravado nos próprios derivados**. Estes
> últimos continuam sem disposição.

### D-PAR-03 — 90 templates de disponibilidade **sem título** derrubam a carga

`rake sfg_etl:load ONLY=availability_templates` morre com
`ActiveRecord::RecordInvalid: Title não pode ficar em branco` — de novo **exceção não
tratada**, sem relatório.

Medido: **90 de 2.705** `availability_templates` com `title` vazio; e **186 de 23.674**
`availability_entries` idem (essa coluna é anulável no destino, então só a primeira
derruba). O destino tem `availability_templates.title` `null: false` mais validação de
presença.

Junto vem uma promessa não cumprida: a decisão `duplicates:availability_templates[…]` em
`db/etl/decisions.yml` diz *"índice único PARCIAL (ignora título vazio)"*. O índice real
do destino é
`index_availability_templates_unique_child_title … WHERE (parent_template_id IS NOT NULL)`
— **não** ignora título vazio. Medido na origem: **2 grupos, 4 linhas**, todas com título
vazio, que colidiriam.

**Reproduzir:** `psql -d sfg_legacy_dump -c "select count(*) filter (where title is null or btrim(title)='') , count(*) from availability_templates"` → `90 | 2705`.

**Dono: usuário** (que título dar a 90 linhas que nunca tiveram um) + a fatia S11 (o
índice parcial prometido).

### D-PAR-05 — o conversor de `providers` que falta **também barra as 169 renegociações**

Com `risk_entries` fechado (**642.447 lidas · 642.447 gravadas**, zero rejeição), o `load`
seguiu para `renegotiations` e morreu em:

> `ActiveRecord::RecordInvalid: Provider é obrigatório(a), Provider não pode ficar em branco`

`Renegotiation` exige `provider`. Como **`providers` não tem conversor** (ACH-PAR-01), o
de-para devolve nulo para todas. Medido na origem: **169 de 169** renegociações têm
`provider_id`, apontando para **147 fornecedores distintos**.

Ou seja: a lacuna do conversor de `providers` **não é "289 linhas que ficam para depois"**
— ela **para a carga** de um módulo inteiro, e é o módulo cuja paridade numérica o razão
mais cita. O `renegotiation_parity` continua verde porque compara **origem contra fórmula**,
sem passar pelo destino; a carga, que passa, não anda.

**Dono: a fatia S4** (escrever `Converters::Providers`).

### D-PAR-04 — o `load` estoura backtrace onde deveria escrever relatório

Os três acima têm a mesma forma: `Converters::Base#write!` chama `save!` e **nada
rescata `ActiveRecord::RecordInvalid`**. O resultado é `rake aborted!` com backtrace,
sem `tmp/etl/load-*.md`, sem linha de anomalia, e o operador sem saber quantas linhas
mais teriam falhado — descobre **uma por vez**, uma execução por defeito.

Há precedente do contrário no mesmo motor: `risk_controls.rb:197` imprime
*"⚠ tipos de limite ausentes — rode `rake reference:seed` antes"*. E o próprio `load`
morre com `ActiveRecord::RecordNotFound: Couldn't find UserType` (em
`Legacy::RoleMap.user_type_for`, via `converters/users.rb:189`) quando se esquece o
`reference:seed` — pré-requisito real do cutover que o motor não confere e o runbook não
carimba.

**Sugestão (não aplicada, é da fatia S14):** `write!` rescata `RecordInvalid`, converte
em anomalia com `key` por modelo e segue o lote; a execução para **no relatório**, com
**todas** as violações contadas.

---

## 4. Três achados que não são defeito, e um que desmente a linha do razão

**ACH-PAR-01 — 1.777 linhas reais de produção sem conversor.** O `dry_run` lista, com o
texto *"conversor … ainda não escrito — o model chega na S4"*, tabelas que **têm dado**:
`providers` **289**, `contracts` **2**, `contract_deals` **272**, `help_categories` **7**,
`help_groups` **5**, `help_items` **25**. (`project_to_carrier_connections`, **1.177**,
saiu da lista às 23:44 de hoje — outro agente entregou o conversor no commit `bda94d8d`,
e a carga aqui rodou **1.177 lidas · 1.177 gravadas** logo depois.) As demais "PULADO"
são tabelas que **não existem na origem** (`charges`, `receipts`, `risk_operation_*`,
`risk_movements`, `structured_operations`, `remunerations`, `project_guarantee_types`,
`project_guarantees`) — dessas não há o que migrar.

**ACH-PAR-02 — o `action_text` de 512 textos ricos não é ordem de carga, é conversor
ausente.** A DEC-120 registrou *"corrige-se carregando `contracts` antes (fatia S12)"*.
Executando: `contracts` **não tem conversor**. Enquanto ele não existir, os 512 corpos
(Indicator 485, HelpItem 25, Contract 2) **não carregam**, e o `dry_run` aborta.

**ACH-PAR-03 — 6 tabelas com dado e sem dono declarado, 8.316 linhas.** O próprio
`introspect` acusa: `trackings` **6.076**, `livetat_auth_abilities` **2.224**,
`livetat_feedback_states` 8, `livetat_feedback_contexts` 4,
`livetat_auth_client_applications` 3, `app_themes` 1. Não estão em `load_order.yml`, nem
em `do_not_migrate` com motivo, nem na lista de infraestrutura.

**ACH-PAR-04 — a nota do DB-082 envelheceu.** Ela diz *"`project_indicator_connections`
nasce SEM a FK para `indicators`: a tabela é da S10"*. O destino **tem** a FK
(`fk_rails_a7c7fd37b7 FOREIGN KEY (indicator_id) REFERENCES indicators(id)`), e as **590
conexões de produção carregaram com ela ligada**, 0 órfãs. A S10 fechou; a justificativa
ficou.

**ACH-PAR-05 — duas promessas de "índice único parcial" que o destino não cumpre.**
`duplicates:carriers[bank_code]` promete *"o índice único passa a ser PARCIAL (ignora
NULL e os sentinelas 888/999/8888/9999)"*; o destino tem
`index_carriers_on_bank_code` **não-único**. `duplicates:renegotiations[project_id+integration_key]`
promete o mesmo; o destino **não tem índice nenhum** nesse par. Nenhum dos dois quebra a
carga — os dois deixam o razão dizendo mais do que o banco faz. (Sentinelas conferidos
na origem: `8888` 181 · NULL 83 · `999` 31 · `9999` 13 · `888` 4.)

**ACH-PAR-06 — os dois casos da DEC-120 que o código resolveu, conferidos na carga.**
`livetat_auth_users.username` vazio: **83 na origem → 83 `NULL` no destino**, e o índice
único parcial `WHERE username IS NOT NULL` aceita. `projects.integration_key` vazia:
**25 na origem → 0 vazias no destino** (83 preenchidas), e o índice único **cheio**
`index_projects_on_integration_key` aceita. Os dois estavam certos; conferidos, não
repetidos.

---

## 5. Uma linha por ID

Legenda: **V** = promovido a `verified` · **M** = continua `migrated`, com o motivo novo.

### 5.1 Esquema e volumetria da origem — o que o `introspect` fechou

| ID | ✓ | O que provou |
| --- | :-: | --- |
| DB-073 | **V** | `rake sfg_etl:introspect SOURCE=db` — o esquema da origem é **lido da origem**: 56 tabelas, **870 linhas de esquema** no relatório, **0 surpresas**. Nenhuma coluna usada pelo ETL é suposta |
| DB-074 | **V** | idem — volumetria medida antes da carga: **782.742 linhas em 56 tabelas**, maior `risk_entries` **642.447** |
| DB-135 | **V** | idem — o portão que aborta em surpresa rodou contra a origem real e passou (`0 surpresas`); a ausência de `db/schema.rb` no legado não deixou nada por adivinhar |
| DB-736 | **V** | `active_storage_attachments` na origem: **0 linhas** (introspect + `psql`). É FONTE, não recriada |
| DB-738 | **V** | `ar_internal_metadata` da origem tem **1 linha, `environment = production`** — exatamente a guarda de `db:drop` que se queria provar. Não é migrada |
| OPS-549 | **V** | `rake sfg_etl:schema_gate` → **PORTÃO VERDE: nenhuma tabela nova sem migration**; 30 órfãs herdadas na allowlist nominal |
| DB-199 | **V** | `dry_run SOURCE=db` conta a integridade que o legado só tinha em aplicação: **7 órfãos** em `livetat_auth_users.default_project_id`, **0** nas duas pontes de projeto |
| DB-167 | **V** | volumetria dos recebíveis medida na origem: **28.131 borderôs** e **58.473 tarifas** |

### 5.2 Cadastros — esquema no destino real **e** dado real carregado

| ID | ✓ | O que provou |
| --- | :-: | --- |
| DB-050 | **V** | `index_companies_on_project_id_and_title` **UNIQUE** existe no destino; na origem **0 grupos duplicados**; carga **112 lidas · 112 gravadas** |
| DB-051 | **V** | `companies.has_safegold_management` `boolean` no destino; **112 de 112** chegaram carimbadas |
| DB-057 | **V** | `psql -d sfg9_dumppar`: `bank_code` **varchar**, `net_worth` **numeric(14,2)**, `subordinated_accounts_percent` **numeric(9,4)**, **sem** `bank_name`; carga **328 · 328** |
| DB-058 | **V** | FK real `fk_rails_d7ae0e9379 (group_id) → carrier_groups(id)` + `index_carriers_on_group_id`. Na origem **0 de 328** portadores têm grupo (a tabela `carrier_groups` tem 0 linhas) — a FK é satisfeita e o `DELETE` direto passa a levantar violação |
| DB-059 | **V** | `carriers.financial_agent` varchar + `index_carriers_on_financial_agent`; 328 linhas reais entraram pela validação de inclusão do model |
| DB-060 | **V** | `carriers.city` e `carriers.uf` existem; `index_carriers_on_uf`; 328 linhas reais passaram pela normalização de UF |
| DB-061 | **V** | `index_carriers_on_legacy_id` **UNIQUE**; depois da carga, **328 de 328** com `legacy_id` |
| DB-062 | **V** | `psql`: **nenhuma** coluna Paperclip (`*_file_name/_content_type/_file_size/_updated_at`) em `carriers`. `attachments` conferiu o acervo: os binários são reanexados por ActiveStorage |
| DB-063 | **V** | `carrier_groups.carriers_count` `integer NOT NULL DEFAULT 0` |
| DB-064 | **V** | `index_segments_on_title` **UNIQUE**; na origem **0 títulos duplicados**; carga **3 · 3** |
| DB-065 | **V** | `index_segments_on_legacy_id` **UNIQUE**; **3 de 3** com `legacy_id` depois da carga |
| DB-066 | **V** | `pg_constraint` de `sub_segments`: a **única** FK é para `users` — **nenhuma** para `segments`, como a DC-13 decidiu. Carga **20 · 20**, 0 títulos duplicados na origem |
| DB-067 | **V** | `projects.segment_id` e `.sub_segment_id` são **uuid** com FK real (`fk_rails_00a25e4c3e`, `fk_rails_dd1e49f9cd`) |
| DB-072 | **V** | as 4 FKs de `projects`, as 2 de `carriers`, a de `sub_segments` e as 2 de cada ponte, todas presentes com índice — contra **zero** no legado. 83 projetos + 328 portadores reais entraram sem violar nenhuma |
| DB-080 | **V** | carga **83 lidas · 83 gravadas** |
| DB-081 | **V** | `index_ptcc_on_project_and_carrier` **UNIQUE** + 2 FKs; carga **1.177 · 1.177** |
| DB-068 | **V** | idem — e na origem **0 pares duplicados, 0 órfãos** dos dois lados |
| DB-082 | **V** | `index_pic_on_project_and_indicator` **UNIQUE** + FK **para `indicators`** (a nota dizia que não haveria — ver ACH-PAR-04); carga **590 · 590**, 0 órfãs |
| DB-083 | **V** | destino: `observation` **text** (era `string(255)`) e `value` **numeric(14,2)**. Origem: a tabela `project_guarantees` **não existe** — nada a migrar, o `dry_run` registra |
| DB-084 | **V** | `index_project_guarantee_types_on_title` e `…_on_integration_key`, os dois **UNIQUE**. Origem sem a tabela; `rake reference:seed` cria as **8** linhas (DEC-86) |
| DB-090 | **V** | a coluna `has_safegold_management` existe em **7 tabelas na origem** (`projects` + 6 filhas) e em **7 no destino** — as mesmas. Nenhuma é ressincronizada (D-30) |
| DB-091 | **V** | `legacy_id` e `importing_id` presentes; `responsible_id` é **FK real** (`fk_rails_c82beb9424 … ON DELETE SET NULL`, era string); `index_projects_on_name` e `…_on_integration_key` **UNIQUE**; carga **83 · 83** |
| DB-092 | **V** | `chk_indicators_scope_matches_project` existe no destino e **529 indicadores reais passaram por ele**: `project` 527 (todos com `project_id`), `global` 2 (nenhum com). `index_indicators_on_scope_and_title` presente |
| DB-089 | **V** | `rake sfg_etl:attachments SYSTEM_TAR=…` — `projects.avatar`: **3 no banco × 3 no acervo**, 0 sem arquivo, 0 com tamanho divergente |
| OPS-052 | **V** | a carga preserva `carriers.legacy_id`: **328 de 328**. O pipeline `Legacy::execute` não é portado, e não precisa ser |
| OPS-053 | **V** | idem para `segments.legacy_id`: **3 de 3** |
| OPS-125 | **V** | `delayed_jobs` na origem: **0 linhas** (introspect). `grep ProgressJob\|Delayed::Job` no repositório: zero. A fila é Sidekiq |
| OPS-493 | **V** | `attachments`: **135 avatares de usuário no banco × 135 no acervo**, 0 órfão dos dois lados, soma de tamanhos idêntica |
| OPS-495 | **V** | `attachments`: **44 anexos de renegociação**, **39.424.330 bytes** conferidos por magic bytes (41 PDF, 1 XLSX), **0 fora da allowlist**, **0 arquivo no acervo sem linha**. Um achado de conteúdo: o anexo **id 45** tem **0 byte** no banco **e** no acervo — existe e está vazio |

### 5.3 Disponibilidade (S11) — esquema conferido, carga barrada

| ID | ✓ | O que provou |
| --- | :-: | --- |
| DB-085 | **V** | as **9** colunas de hierarquia da origem, contadas no esquema real (`numeric_first_level`, `numeric_second_level`, `numeric_third_level`, `max_level`, `is_upper_level`, `position`, `parent_level`, `parent_position`, `top_parent_id`), viram **3** no destino (`level`, `position`, `sort_key`) |
| DB-120 | **V** | tabela **única** com `type NOT NULL` e `index_availability_templates_on_tree_order (type, project_id, sort_key)` — a STI é do banco, não só do model |
| DB-121 | **V** | `is_global boolean NOT NULL DEFAULT false`, `project_id` anulável, e `index_availability_templates_unique_root_title (type, project_id, title) WHERE parent_template_id IS NULL` |
| DB-122 | **V** | `index_availability_templates_unique_global_per_project (project_id, global_availability_template_id) WHERE … IS NOT NULL` + FK `project_id → projects` |
| DB-124 | **V** | `is_adjusted` **não existe na origem** — medido no esquema real das 31 colunas de `availability_templates`. O destino a cria com `NOT NULL DEFAULT false`. A migration do legado nunca rodou, e agora está provado no dado |
| DB-125 | **V** | `original_value` **não existe na origem** — as 11 colunas reais de `availability_entries` estão listadas no relatório do `introspect` |
| DB-126 | **V** | `company_id` **não existe na origem**: em produção **toda** linha é consolidação. `is_consolidation` explícito no destino é a única forma de não inferir |
| DB-128 | **V** | `is_locked`, `locked_at`, `locked_message` e `locked_by_id` (FK `→ users ON DELETE SET NULL`) presentes; a origem tem `is_locked/locked_at/locked_message` e **não** tem autor |
| DB-129 | **V** | `job_state` varchar + `job_report` **jsonb** no destino; na origem `job_report` é **text** |
| DB-130 | **V** | `availability_entries.has_safegold_management` existe **na origem** (integer) e **no destino** (boolean NOT NULL) |
| DB-131 | **V** | os 12 irmãos ordenam por `level`/`position`/`sort_key` no destino; a origem ordena por `position` **varchar** + `parent_position` varchar + 3 níveis numéricos |
| DB-132 | **V** | `should_insert_on_existing_projects boolean NOT NULL DEFAULT true`, presente nos dois lados |
| DB-133 | **V** | as 4 FKs, os `null: false` e os **2 índices únicos parciais** de `availability_entries` existem; e a carga **é** barrada antes da 1ª escrita quando a origem viola — provado (é o D-PAR-03), embora hoje ela seja barrada por backtrace e não por relatório (D-PAR-04) |
| DB-134 | **V** | `default_position` **não existe na origem** — zero ocorrência no esquema real. O destino a mantém, sem papel de ordenação (D-126) |
| DB-123 | **M** | o esquema e os índices existem e estão conferidos; a **carga de `availability_entries` não roda** porque `availability_templates` para antes, nos 90 títulos vazios (**D-PAR-03**) |
| BE-148 | **M** | a consolidação por template base só é comparável com as 2.705 árvores e as 23.674 entradas carregadas. **Bloqueada pelo D-PAR-03**, não pela carga |

### 5.4 Recebíveis e renegociações

| ID | ✓ | O que provou |
| --- | :-: | --- |
| DB-159 | **V** | `receivable_kinds`: carga **7 lidas · 7 gravadas** |
| DB-160 | **V** | `movement_kinds`: carga **18 · 18** |
| DB-162 | **V** | `charges` **não existe na origem** (introspect, 56 tabelas). Nada a migrar; a tabela do destino nasce vazia |
| DB-163 | **V** | `receipts` **não existe na origem**. Idem |
| DB-164 | **V** | idem — as colunas de data e título da operação não têm de onde vir |
| DB-165 | **V** | as duas metades (`structured_operations.receipt_id`, `risk_operations.receipt_id`) existem no destino; **nenhuma das três tabelas existe na origem** — não há dado para conciliar |
| DB-197 | **V** | `renegotiations.has_safegold_management` existe na origem e no destino; `renegotiation_parity SOURCE=db` compara **47.170** campos e não acusa esse |
| DB-194 | **M** | os conversores estão escritos e os renomes mapeados, mas a carga de `receivable_entries` **para nos 32 borderôs com `NaN`** (**D-PAR-02**) — o de-para não chega a ser exercitado |
| DB-150 | **M** | idem — **D-PAR-02** |
| DB-154 | **M** | idem — **D-PAR-02** |
| DB-155 | **M** | idem — **D-PAR-02** |
| DB-156 | **M** | idem — **D-PAR-02** |
| DB-157 | **M** | idem — **D-PAR-02** |
| OPS-150 | **M** | a importação do legado **é** o ETL, e ele foi executado; para em `receivable_entries` por **D-PAR-02** |
| OPS-151 | **M** | o recálculo em massa precisa dos 28.131 borderôs carregados. **D-PAR-02** |
| OPS-197 | **V** | `rake sfg_etl:renegotiation_fixups` (ensaio) executado contra o dado real: **0** projeto sem empresa, **0** ordinal fora, **0** renegociação divergente, **0** contador fora do real. Os fixups existem e não têm o que corrigir |
| DB-568 | **V** | `renegotiation_parity SOURCE=db`: **47.170 comparações · 47.162 iguais · 0 regressões · 8 mudanças declaradas (D-45)**. `total_value_with_desagio` fica fora porque a coluna **não existe no dump** (migration de 2022 que nunca subiu) |

### 5.5 Tabelas conferidas contra o inventário `data-schema`

O motivo escrito nestas linhas era *"conferido contra o inventário `data-schema`"* — um
documento. Agora a conferência é contra **o esquema real da origem**, lido pelo
`introspect` (870 linhas, 0 surpresas), e contra o **destino real**.

| ID | ✓ | O que provou |
| --- | :-: | --- |
| DB-287 | **V** | `resource_sources` no destino tem único em `title`, em `integration_key` e em `legacy_id`; a carga leu **6 · 6** da origem |
| DB-293 | **V** | as **6** linhas de produção (não as 7 do mapa) conferidas: `rake reference:seed` cria **6**, e a carga da origem lê **6** |
| DB-295 | **V** | a convenção `integer → boolean` (`!= 0 → true`): o `dry_run` contra o dado real devolve **ZERO** ocorrência de valor `2+` em toda a origem — a regra nunca é exercida na prática, e agora isso está medido, não suposto |
| DB-550 | **V** | uma única família `segments` — 3 linhas reais carregadas nela; `schema_gate` verde |
| DB-573 | **V** | os **15 valores** e os **5 totais derivados** conferidos no esquema **real** da origem (25 colunas em `risk_entries`) e no destino (26). Carga do dado real **completa: 642.447 lidas · 642.447 gravadas, zero rejeição** |
| DB-581 | **V** | `structured_operations` **não existe na origem** (56 tabelas conferidas) — a tabela do destino não tem par a conciliar; o esquema confere coluna a coluna |
| DB-585 | **V** | uma única família `indicators` — **529 linhas reais** carregadas nela, com o CHECK de `scope` ligado |
| DB-543 | **M** | há **uma** tabela de aplicação-cliente no `schema.rb`, sim. Mas `livetat_auth_client_applications` tem **3 linhas na origem** e o `introspect` a lista como **tabela com dado e sem dono declarado** (ACH-PAR-03): não está em `load_order.yml`, nem em `do_not_migrate` |
| DB-546 | **M** | `contracts` tem **2 linhas na origem** e **não tem conversor** (ACH-PAR-01). É também o que trava os 512 textos ricos (ACH-PAR-02) |

### 5.6 Fornecedores, textos ricos e os dois que o dump respondeu com "nunca"

| ID | ✓ | O que provou |
| --- | :-: | --- |
| DB-052 | **M** | o esquema do destino confere (`index_providers_on_project_id_and_document_type_and_document` **UNIQUE … WHERE document IS NOT NULL**, `activities` **jsonb** único, nenhuma coluna Paperclip). Mas **não existe conversor** e a origem tem **289 fornecedores**: paridade de dado impossível hoje — e o motivo não é mais a carga |
| DB-053 | **M** | idem — `document_type varchar(4)` / `document varchar(14)` cobrem CPF e CNPJ; sem conversor |
| DB-054 | **M** | idem — os campos da ReceitaWS (`legal_name`, `trade_name`, `status`, `opened_at`, `status_changed_at`, `cnpj_fetched_at`) existem; sem conversor |
| DB-055 | **M** | idem — `cnaes` + `atividades` num **único** `activities jsonb` (D-25); sem conversor |
| DB-056 | **M** | idem — Paperclip não portado, `psql` confirma zero coluna de anexo; sem conversor |
| DB-088 | **M** | `action_text_rich_texts` é reusada de ponta a ponta, sem migration (7 colunas conferidas no destino). Mas os **512 corpos não carregam**: o conversor existe e o `dry_run` **aborta** porque `contracts` não tem conversor (ACH-PAR-02) |
| DB-737 | **M** | os **512** corpos estão medidos na origem (Indicator 485, HelpItem 25, Contract 2) e há **zero** corpo URL-escapado além do 1 já declarado. A **carga** deles continua barrada por ACH-PAR-02 |
| BE-127 | **M** | **resposta definitiva, e é "nunca"**: `is_adjusted` e `original_value` **não existem na origem** (medido no esquema real). Não há oráculo de produção para o decaimento por dias úteis, e não haverá — este item **não depende de carga nenhuma**. Fica coberto pelo golden de `spec/lib/sfg/business_days_spec.rb` |
| BE-052 | **M** | `risk_controls` carregou **600 · 600** e `risk_entries` está em curso; o resumo por empresa só é comparável com a série completa. Não é mais "espera a carga": é "espera esta carga terminar" |

---

## 6. O que precisa do usuário

1. **Os 32 borderôs com `NaN`** (D-PAR-02) — bloqueador de cutover, decisão de negócio.
   A decisão já assinada cobre **1** tarifa; os 32 borderôs são outra coisa.
2. **Os 90 templates de disponibilidade sem título** (D-PAR-03) — que título dar, ou
   autorizar um rótulo de carga.
3. **`custom:receivable_entries`** (35.813 anomalias em 2 padrões, Q-B19 e DB-154) e
   **`custom:renegotiation_attachments`** (88) continuam sem disposição, e continuam
   abortando o `dry_run`.
4. **1.777 linhas sem conversor** (ACH-PAR-01) e **8.316 linhas sem dono declarado**
   (ACH-PAR-03): decidir se migram, e de quem é a fatia. O de `providers` é o mais
   urgente — ele **para a carga das 169 renegociações** (D-PAR-05).

## 6.1 Portões desta passada

- `rspec` (suíte inteira, banco próprio `sfg9_par_test`): **2.824 exemplos, 0 falhas,
  5 pendentes**. A linha de base do briefing era 2.749 — outros agentes acrescentaram
  exemplos no mesmo dia; **falha nova, nenhuma**.
- `rspec spec/lib/sfg/etl` **com** `SFG_DUMP` e `SFG_SYSTEM_TAR`: **32 exemplos, 0 falhas**.
- `npx vitest run` no `frontend`: **verde** (nenhum arquivo de front foi tocado).
- `rake sfg_etl:ledger_gate`: passa nos **5** critérios.
- `rake sfg_etl:schema_gate`: **PORTÃO VERDE**.

## 7. Higiene

- Bancos criados por esta passada: `sfg9_dumppar` e `sfg9_par_test` — **descartáveis, e
  descartados ao fim**. Nada foi escrito em `sfg9_dev` nem em `sfg9_test`.
- `sfg_legacy_dump` foi usado **somente para leitura**.
- O `decisions.yml` do repositório **não foi tocado**. A entrada provisória que destravou
  o ensaio vive num arquivo fora do repositório, passado por `DECISIONS=`.
- Nenhum dado real foi commitado (DEC-123). Ids aparecem; nome, e-mail, CPF e valor
  identificável, não.
- **O dump é de 31/05/2025.** Ele prova que as fórmulas batem e que o pipeline funciona.
  A conferência de virada acontece **no servidor** (DEC-124), com o dado de lá.

### D-PAR-06 — a unicidade de `integration_key` é acréscimo do ai9, e torna o laço do slug inalcançável

Apareceu escrevendo o spec de BE-095 (27/08), não por leitura: dois projetos de
nomes **diferentes** que transliteram para o mesmo slug (`Açúcar` e `Acucar`) são
recusados — mas em `integration_key`, não em `slug`.

| | legado (`app/models/project.rb:128`) | ai9 (`app/models/project.rb:90`) |
|---|---|---|
| `formal` / `name` | `uniqueness: true` | único |
| `integration_key` | **derivado, sem validação** | `uniqueness: { case_sensitive: false }` |

Consequência prática, e é ela que importa: o **laço de desambiguação do `slug`**
(`acucar` → `acucar-2`) só roda quando a chave de integração é informada à mão.
Pelo caminho comum da tela ele nunca é alcançado, porque `integration_key` barra
primeiro — e essa **não tem laço nenhum**: o segundo projeto é recusado com "já
está em uso" em vez de ganhar sufixo.

**Impacto medido: nenhum na base atual** — 12 projetos, `GROUP BY
integration_key HAVING count(*) > 1` devolve vazio. Não medi a origem legada
(o `psql` do dump não estava de pé nesta passada), então o que afirmo vale para
o que já está carregado. É, de todo modo, uma divergência de **tela**: ela morde
no cadastro novo, não na carga.

**Sem decisão registrada.** Não é DEC-30 aplicado e revisado: é uma restrição que
entrou junto com o model. As duas saídas são pequenas e opostas — dar ao
`integration_key` o mesmo laço que o `slug` tem (e aí os dois funcionam), ou
soltar a unicidade como no legado (e aí o laço do slug volta a ser alcançável).
Fica **em aberto para o Vinícius**, fora do caminho da demo.


### D-PAR-07 — `legacy_id` tem DOIS significados, e o que venceu não é o que a DEC-12 pediu

Apareceu ao tentar fechar DB-157 em 27/08. O bloqueio antigo (**D-PAR-02**, os 32
borderôs com `NaN`) já não vale — a última reconciliação dá
`receivable_entries` **28131 = 28131, 0 divergências**. O que restou é outra
coisa, e é semântica.

**A origem tem as duas colunas.** O `introspect` lista, em
`receivable_entries`: `id bigint` (PK) e `legacy_id integer`, esta com índice
único próprio. A `legacy_id` da origem é a proveniência do ETL Django→Rails de
2021 — 17.610 linhas preenchidas em produção.

**O destino usa o nome para outra coisa.** Todos os conversores gravam
`legacy_id: row['id']`, e não é descuido: `converters/base.rb:212` define
`natural_key(row) = { legacy_id: row[legacy_pk] }`. É por essa coluna que a
carga é idempotente e retomável. Trocar o significado quebraria o `resume` de
todas as 32 tabelas.

**Consequência: a `legacy_id` do Django não é migrada.** O conversor só a LÊ, e
só para o relatório de anomalia da Q-B19 (`receivable_entries.rb:479`); nunca a
grava. Depois da carga, a coluna do destino contém 28.131 ids do Rails legado,
não os 17.610 ids do Django.

**Isso contraria o que está escrito.** O comentário da migration diz
textualmente: *proveniência do ETL Django→Rails de 2021 (…17.610 linhas
preenchidas em produção). O ETL não é portado; a coluna sim (DB-157)*. A coluna
foi criada; o dado que ela deveria carregar, não.

**Não decidi sozinho, e por quê.** A DEC-12 pediu a proveniência do Django; a
convenção do motor pede o id do sfg. As duas são razoáveis e não cabem na mesma
coluna. As saídas:

| | o que custa |
|---|---|
| **a)** aceitar a convenção e descartar a proveniência Django | uma linha em `removed-features.md`; perde-se o rastro de 17.610 borderôs até o sistema de 2021 |
| **b)** coluna separada (`django_legacy_id`) | migration + conversor + recarga daquela tabela; nada quebra |

**Nada disso afeta a demonstração** — a coluna não aparece em tela nenhuma. Fica
para o Vinícius. O comentário da migration foi corrigido para parar de afirmar o
que não acontece.
