# Proposal: S8 — Operações estruturadas e remuneração

## Why

A operação estruturada é o segundo agregado financeiro do Safegold — e é onde mora a
**única fórmula de faturamento do sistema**: `Remuneration` × `Receipt`. É o dinheiro que o
Safegold cobra do próprio cliente.

Esta fatia existe por quatro razões:

1. **A fórmula de remuneração tem zero cobertura e é dinheiro cobrado.**
   `../sfg/app/models/receipt.rb:41-66` faz `value = operation_value × (fee.to_f / 100.0)`
   — `decimal(15,2) × Float` gravado em `decimal(15,2)`, com arredondamento **acidental**
   vindo do cast. Não há pro-rata, não há prazo: nem `agreed_rate`, nem
   `issue_date`/`due_date`, nem `balance` entram. Replicar isso por **DEC-02** (melhoria
   **declinada** pelo usuário) só é honesto com **golden test por fórmula**, porque o legado
   **não tem nenhum teste** (**D-114**).
2. **Contrato C2 — um serviço, chamado pela tela E pela gravação.**
   `Structured::RemunerationCalculator` é a única implementação. A prévia do recibo na tela
   de cobrança chama **o mesmo serviço** que grava — é o que impede prévia e gravação de
   divergirem (**D-09**).
3. **Duas IDORs e uma superfície sem autenticação.** `structured_operations#search`
   (BE-280) e `#update` (BE-286) **descartam o escopo de projeto** ao receber um id
   (família D-01/D-16/D-29/D-76/D-100). Pior: os controllers dedicados desta unidade herdam
   `requires_current_user? == false` — `search`/`create`/`update`/`destroy` **não exigem
   login pelo `before_action`** (BE-309/FE-309).
4. **Uma perda de integridade que corrompe faturamento emitido.**
   `Remuneration has_many :receipts` **sem `dependent:`**: apagar uma remuneração deixa
   recibos órfãos apontando para `remuneration_id` inexistente e, como `Receipt belongs_to
   :remuneration` é obrigatório, qualquer save posterior desses recibos passa a falhar
   (BE-303).

**O que a operação estruturada NÃO é** (correção **C-10** do mapa): apesar de o formato de
colunas ser quase igual ao da operação de risco, ela **não tem movimentos, não tem
subtipos, não tem pré-faturamento efetivo, não tem prorrogação e não tem renovação**, e o
`balance` **nunca é movimentado**. São dois agregados distintos que compartilham
vocabulário. Tratá-los como "a mesma coisa com nome diferente" produziria uma abstração que
não serve para nenhum dos dois.

## What Changes

Entrega ponta a ponta as sub-fatias **E1, E2 e E3** do mapa de bloco
(`.migration-ai9/map/risk-indicators.md` §1) e a parte de **X1** que pertence a este
domínio:

- **E1 — operações estruturadas e tipos.** Dados, CRUD, lista, formulário, detalhe e
  catálogo de tipos. Escopo de projeto fechado, paginação real, 422 de verdade.
- **E2 — remunerações e a fórmula do recibo.** A fórmula de faturamento replicada com o
  mesmo cast float→decimal e coberta por golden.
- **E3 — fontes e tipos de recurso.** `resource_sources` é usada de verdade por Recebíveis;
  `resource_kinds` é candidata a descarte (**Q-R5**) e fica atrás de um portão de decisão.
- **X1 (parte estruturadas)** — 9 descartes com evidência de varredura.

**Não** entrega: nada de `risk` (**S5**/**S7**), nada de indicadores (**S10**), e nada de
`receipts`/`charges` — a tabela `receipts` e o `Charge#calc!` são do bloco vizinho. **A
fórmula é desta fatia; a materialização é de lá** (`DB-290`).

### Dependências

| Direção | O quê |
| ------- | ----- |
| Consome de **S0** | `current_project!`, `ProjectScoped`, papéis + hierarquia (C3), `user_is_readonly` |
| Consome de **S0/S5 (DS)** | `DataTable`, `Pagination`, `MoneyInput`/`PercentInput`, `EmptyState`/`ErrorState`, `DateRangePicker` |
| Consome de **S3/S4** | `Carrier`, `Company`, `Project` |
| Consome de **S5** | `RiskOperationType` — é a classe **LIQ** das remunerações |
| Consome de **S7** | `RiskOperation` como `operation_class` da classe LIQ; `available_for_receipt` |
| Consome de **`charges`/`receipts`** | a tabela `receipts` e o `Charge#calc!` (bloco vizinho). **E2 não fecha sem este handshake** |
| Entrega para **`receivables`** | `resource_sources` — `ReceivableEntry` exige `resource_source_id` |
| Entrega para **`charges`** | `Structured::RemunerationCalculator` e a política de arredondamento |

### Decisões que governam esta fatia

| Decisão | Efeito prático aqui |
| ------- | ------------------- |
| **DEC-01** (melhoria **declinada**, D-93) | `original_balance = -(|valor|)`; o detalhe exibe saldos **negativos** e o formulário exibe o absoluto. **QA não deve ler como regressão** |
| **DEC-02** (melhoria **declinada**, D-104) | A sequência exata de `value = operation_value × (fee.to_f / 100.0)` é replicada, inclusive o arredondamento acidental do cast. Armazenar em `decimal` **não** obriga a calcular em `decimal` |
| **C1** | Escopo por projeto **no endpoint**; `structured_operation_id` deixa de descartar o escopo |
| **C2** | `Structured::RemunerationCalculator` chamado pela prévia **e** pela gravação |
| **C3** | Hierarquia do ai9; todo teste de autorização verifica **os dois lados** |
| **DEC-09** | Nada é inventado: sem baixa de saldo, sem remuneração variável, sem export |
| **Princípio 6b** | O que parecer errado na base e não bloquear vira linha em `upstream-flags.md` |

## Impact

- **Afetado:** `backend/db/migrate` (5 tabelas da unidade), `backend/app/models/{structured_operation,structured_operation_type,remuneration,resource_source,resource_kind}.rb`,
  `backend/app/services/structured/`, `backend/app/controllers/api/v1/{structured_operations,structured_operation_types,remunerations,resource_sources,resource_kinds}.rb` + entities,
  `backend/db/seeds/`, `frontend/src/features/structured-operations/`, `useNavItems.ts`.
- **Não afetado:** o legado `sfg` (read-only); `risk`; `indicators`.
- **Mudanças visíveis** (registrar em `improvements-log.md`):
  **IMP-R2** — as listas de operações estruturadas, tipos e remunerações passam a **paginar
  de verdade** (hoje o `limit`/`offset` é descartado e a lista volta inteira, em ordem
  indefinida). A tela deixa de trazer tudo de uma vez.
  **IMP-R4** — operação com data nula **passa a aparecer** quando não há filtro de período
  (hoje o `DATE(NULL)` a exclui em silêncio).
- **Risco principal:** `DB-296`. Padronizar armazenamento (`decimal(14,2)` para valores,
  `decimal(7,4)` para taxas) **sem** alterar a sequência de cálculo. `Charge#calc!` soma
  esses valores — mudança de precisão afeta cobrança. Golden antes e depois.

## IDs de inventário cobertos (98)

Estratégia copiada de `.migration-ai9/map/risk-indicators.md` §2.4.
**Placar: 74 `build` · 11 `build?` · 9 `drop` · 4 `adapt`.**

### `structured-operations` — backend (§2.4)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-280 | build | `SVC/structured/operation_service.rb#index`; `EP/structured_operations.rb` — **corrige IDOR** |
| BE-281 | build | busca `q` em `carriers.title` **ou** `structured_operations.title`. **Replicar** o alcance |
| BE-282 | build | `#in_period` — intersecção emissão→vencimento; sem `from`/`to`, predicado **não aplicado** |
| BE-283 | build | allowlist de ordenação; chave desconhecida → **400** (hoje 500) |
| BE-284 | build | `X-Total-Count` real (hoje o total é calculado **depois** do limit/offset) + teto de `per_page` |
| BE-285 | build | `#create` — `:id` sai do permit (mass assignment, família D-60/D-68) |
| BE-286 | build | `#update` — busca **com** escopo de projeto (**IDOR**) |
| BE-287 | build | `#destroy` — 422 real; hoje `errors.any? ? :ok : :ok` |
| BE-288 | **drop** | `new`/`edit` do controller dedicado: `NoMethodError` em 100% das chamadas |
| BE-289 | **drop** | 5 `index` e 3 `show` renderizam templates inexistentes → `MissingTemplate` |
| BE-290 | build | `MOD/structured_operation.rb` — `title` cai para `carrier.title`; `carrier_id` inválido → 422 |
| BE-291 | build | `project_id` **sempre** derivado da empresa; trocar a empresa passa a exigir confirmação (**Q-R13**) |
| BE-292 | **build?** | `balance = original_balance` em todo save. **Q-R3**, ver "Como cada `build?` foi resolvido" |
| BE-293 | build | `validates` — **replicar as ausências** (Q-R7) |
| BE-294 | build | `scope :available_for_receipt` (`receipt_id: nil`); `Receipt#fetch` passa a 409/422, não 500 |
| BE-295 | build | `is_ended`, `is_on_variable`, `agreed_rate` persistidos e **sem consumidor** — não inventar (**Q-R14**) |
| BE-296 | build | `SVC/structured/operation_type_service.rb#index` — paginação real; filtro de ativo opcional |
| BE-297 | build | `#create` — `integration_key` derivada do título, com **unicidade** (**Q-R15**) |
| BE-298 | build | `#update` — `title`, `is_default` e `integration_key` imutáveis **no servidor** |
| BE-299 | build | `#destroy` — guarda única de `is_default` + `restrict_with_error`, com 422 legível |
| BE-300 | build | `SVC/structured/remuneration_service.rb#index` — paginação, ordenação e filtro por classe |
| BE-301 | build | `#create` — unicidade (projeto, classe, tipo); `project_id` forçado; inclusão de `operation_type_type` (**Q-R16**) |
| BE-302 | build | `#update` — escopo de projeto; imutabilidade no servidor; recibos emitidos **não** são recalculados |
| BE-303 | build | `#destroy` — `restrict_with_error` (hoje deixa **recibos órfãos**) |
| BE-304 | build | `MOD/remuneration.rb` — `operation_class`, `beauty_type` `"LIQ"`/`"EST"`; tipo inválido → 422, não 500 |
| BE-305 | build | **`SVC/structured/remuneration_calculator.rb`** — a fórmula. **DEC-02**, golden obrigatório (**Q-R17**) |
| BE-306 | build | `#candidates` — cada candidato já vem calculado; `operation_class` nil deixa de dar 500 (**Q-R18**) |
| BE-307 | **build?** | `resource_kinds#index`. **Q-R5** |
| BE-308 | build | `resource_sources#index` — a entidade **realmente usada** (**Q-R19**) |
| BE-309 | **drop** | `structured_operation_taxes`: 8 rotas, **zero** controller, model, view, migration e tabela |
| BE-720 | **build?** | `EP/resource_kinds.rb` (drawer). **Q-R5** |
| BE-721 | **build?** | `resource_kinds#show` → 404 estruturado. **Q-R5** |
| BE-722 | **build?** | `resource_kinds#create`. **Q-R5** |
| BE-723 | **build?** | `resource_kinds#update`. **Q-R5** |
| BE-724 | **build?** | `resource_kinds#destroy` — 422 real. **Q-R5** |
| BE-725 | build | `EP/resource_sources.rb` (drawer) + autorização de servidor |
| BE-726 | build | `resource_sources#show` → 404 estruturado |
| BE-727 | build | `resource_sources#create` — `title` único, `integration_key` derivada no create |
| BE-728 | build | `resource_sources#update` — `integration_key` **explicitamente imutável** |
| BE-729 | build | `resource_sources#destroy` — `restrict_with_error` que **realmente dispara**; 422 |

### `structured-operations` — frontend (§2.4)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| FE-280 | build | `FE/structured-operations/pages/StructuredOperationsPage.tsx` — corrige 2 copy-paste de rótulo |
| FE-281 | build | estado de carregamento; o modo `silent` vira `keepPreviousData` |
| FE-282 | build | `DS/EmptyState.tsx` — "primeiro uso" passa a existir |
| FE-283 | build | `DS/ErrorState.tsx` — hoje o `failure` do proxy é **vazio** |
| FE-284 | build | `SearchBox.tsx` — debounce 300 ms, busca só de espaços abortada |
| FE-285 | build | `DS/DateRangePicker.tsx` — corrige o bug do ano |
| FE-286 | build | filtros com `.all` × cadastro com `.active` (decisão **B-04**) |
| FE-287 | build | `DS/DataTable.tsx` tri-state; a chave `company` **sai da allowlist** (decisão **B-13**) |
| FE-288 | build | `DS/Pagination.tsx` — passa a funcionar com o total real |
| FE-289 | build | `OperationRow.tsx` — BRL, `contract_number` com fallback "-", `agreed_rate` com 2 casas nas duas telas |
| FE-290 | build | Ver mais / Editar / Remover, rotas reais (D-92) |
| FE-291 | build | guarda de portador e de empresa; corrige o rótulo "Cadastrar recebível" |
| FE-292 | build | confirmação de exclusão com mensagem de negócio (hoje a bloqueada cai no `success`) |
| FE-293 | build | `OperationForm.tsx` — duas colunas; sai a gambiarra do `hidden_field :id` |
| FE-294 | build | máscaras via `DS/MoneyInput`/`DS/PercentInput` |
| FE-295 | build | barra de ação explícita que **diz o que falta** (hoje a ação some sem mensagem) |
| FE-296 | **drop** | `update_values()` casa com **zero elementos**: no-op silencioso |
| FE-297 | **build?** | datas na edição. **Q-R10**, ver "Como cada `build?` foi resolvido" |
| FE-298 | build | bloqueios sem portador / sem empresa; corrige "operação de estruturada" |
| FE-299 | build | `OperationDetailPage.tsx` — **saldos exibidos com sinal** (DEC-01); id inexistente → **404** (**Q-R20**) |
| FE-300 | build | `OperationTypesPage.tsx` — "Excluir" ausente para `is_default`, **com a mensagem dizendo por quê** |
| FE-301 | build | `OperationTypeDrawer.tsx` — corrige 2 copies de outro domínio; sucesso passa a emitir toast |
| FE-302 | build | exclusão de tipo: o `$.ajax` sem `error` fazia o clique **não fazer nada** |
| FE-303 | build | `RemunerationsPage.tsx` — Classe (LIQ/EST), Operação, Taxa (%); ordenação e paginação |
| FE-304 | build | `RemunerationDrawer.tsx` — um select controlado no lugar de dois sobrepostos (**Q-R21**) |
| FE-305 | build | `DS/PercentInput.tsx` — **sem limite de faixa hoje** (**Q-R16**) |
| FE-306 | build | deep-links `/remunerations/add` e `/remunerations/:id/edit` — corrige 2 defeitos de URL |
| FE-307 | **build?** | `ResourceKindsPage.tsx` — tela **sem entrada de menu**. **Q-R5** |
| FE-308 | build | `ResourceSourcesPage.tsx` — Título/Chave ordenáveis (**Q-R22**) |
| FE-309 | adapt | policy do **AUTH.S3** — hoje os controllers **não exigem login pelo `before_action`** |

### `structured-operations` — dados (§2.4)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| DB-280 | build | `MIG/*_operacoes_estruturadas.rb` — índices, `observation` → `text`, `agreed_rate` → `decimal(9,4)` |
| DB-281 | build | `receipt_id` com índice **obrigatório**; relação circular decidida junto com `charges` |
| DB-282 | build | as 5 migrations: **nenhuma** declara FK; todas passam a ter, com `ON DELETE RESTRICT` |
| DB-283 | build | `MIG/*_tipos_de_operacao_estruturada.rb` — únicos em `title` e `integration_key` (**Q-R15**) |
| DB-284 | build | `MIG/*_remuneracoes.rb` — único composto (projeto, classe, tipo); `value` float → `decimal(7,4)` |
| DB-285 | build | `remunerations.title` **continua desnormalizado** (decisão **B-06**) |
| DB-286 | **build?** | `MIG/*_tipos_de_recurso.rb`. **Q-R5** |
| DB-287 | build | `MIG/*_fontes_de_recurso.rb` — único em `title` (**Q-R19**) |
| DB-288 | build | `legacy_id` com índice único, mapeando `durecliq.url_id` do banco Django anterior |
| DB-289 | **drop** | `receivable_entries.resource_kind_id` — **sempre NULL**; descarte **condicionado ao dump** |
| DB-290 | adapt | contrato com `charges`/`receipts`: índice único obrigatório em (operação, projeto, tipo) |
| DB-291 | **drop** | `structured_operation_taxes`: nenhuma migration cria, nenhum model referencia |
| DB-292 | build | seed dos 4 tipos, **todos `is_default`**; as 4 `integration_key` são **contrato** |
| DB-293 | build | seed de `resource_sources` — 7 linhas; **coexistem com os importados** no ETL |
| DB-294 | **build?** | seed de `resource_kinds` — 5 linhas. **Q-R5** |
| DB-295 | build | 9 flags integer → boolean, mapeamento **`≠ 0 → true`**, com dry-run listando os `2+` |
| DB-296 | build | valores `decimal(14,2)` e taxas `decimal(7,4)`, **mantendo a sequência de cálculo de BE-305** |
| DB-297 | build | `created_by_id`/`updated_by_id` com FK real, preenchidos no servidor (hoje `user_id` é forjável) |

### `structured-operations` — operação (§2.4)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| OPS-280 | **drop** | 8 rotas de `structured_operation_taxes`, 0 código, nenhum link |
| OPS-281 | **drop** | 5 `index` e 3 `show` → `MissingTemplate` (500) |
| OPS-282 | **drop** | `Dev.ilike` → `ILIKE` nativo (DEC-05) |
| OPS-283 | build | predicado de período **não aplicado** quando não há filtro (fim da sentinela de ±2000 anos) — **IMP-R4** |
| OPS-284 | build | textos de ajuda carregados **uma vez**, não `YAML.load_file` por requisição (**Q-R9**) |
| OPS-285 | adapt | ETL: **código descartado (D-105), colunas `legacy_*` preservadas** |
| OPS-286 | adapt | `useNavItems.ts` — 4 itens de menu; corrige os títulos de aba copiados (**Q-R22**) |
| OPS-287 | build | `spec/services/structured/remuneration_calculator_spec.rb` — **zero cobertura hoje** |
| OPS-288 | build | allowlist validada no `params do … end` do Grape, devolvendo **400** |
| OPS-289 | build | formatação sai do backend (monkey-patch em `Integer`/`Float`/`BigDecimal`) e vai para `Intl` no front |

## Como cada `build?` foi resolvido (11)

| ID | Pergunta | Resolução nesta fatia |
| -- | -------- | --------------------- |
| **BE-292** | O `balance` da operação estruturada deveria evoluir? (**Q-R3**, D-73) | **Replicar o reset exatamente** e cobrir com golden: `original_balance = -(|valor|)` e `balance = original_balance` em **todo** save, inclusive quando só a observação muda. **Não inventar mecanismo de baixa** — a varredura completa confirma que nada no legado inteiro movimenta esse saldo. A coluna fica documentada como decorativa. Tarefa de decisão **T-D6** (é a maior ambiguidade financeira do bloco) |
| **FE-297** | As datas de operação existente são editáveis? (**Q-R10**) | **Regra de servidor**, a mesma que S7 aplica à operação de risco. A spec de `FE-297` já resolve assim ("as datas não são editáveis pela tela, **e a API aplica a mesma regra**"). Adotado, e **alinhado com S7** (a fatia irmã), para os dois módulos irmãos não terem semânticas diferentes para a mesma pergunta. Tarefa de decisão **T-D5**, compartilhada com S7 |
| **BE-307**, **BE-720**, **BE-721**, **BE-722**, **BE-723**, **BE-724**, **FE-307** (7 IDs) | `resource_kinds` é portado ou descartado? (**Q-R5**) | **Portão de decisão.** A **superfície não é construída** até o número chegar. Sem item de menu, com `receivable_entries.resource_kind_id` **nunca preenchido** e dois flags sem consumidor, construir 7 IDs de CRUD pode ser trabalho por nada — e descartar sem o número pode ser perda de dado. Tarefa de decisão **T-D7**: `SELECT COUNT(*) FROM receivable_entries WHERE resource_kind_id IS NOT NULL` no dump. **Zero → os 7 IDs viram `dropped` com evidência** (junto com `DB-289`); maior que zero → a superfície é construída como o mapa descreve |
| **DB-286**, **DB-294** | A tabela e o seed de `resource_kinds` são criados? | **Sim, mesmo com a superfície bloqueada.** A tabela e as 5 linhas do seed nascem: preservar dado é barato, perder é irreversível. Se T-D7 vier zero, a tabela é removida numa tarefa única e explícita, não por omissão. O título sem acento ("Antecipacao") só é corrigido se a entidade sobreviver |

## `drop` — motivo registrado (9)

Cada um vira linha `dropped` no `parity-ledger.md` **com a evidência da varredura**, nunca
por omissão.

| ID | Motivo | Evidência |
| -- | ------ | --------- |
| **BE-288** | Código morto: `structured_operations#new`/`#edit` do controller dedicado definem `@companies`/`@carriers`/`@operation_types`, mas a view exige `@first_company`/`@first_carrier`/`@structured_operation_types` → **`NoMethodError` (500) em 100% das chamadas** | O caminho **vivo** é `ConsoleController#index:206-231`, e é ele que vira a tela React |
| **BE-289** | Código morto: 5 `index` e 3 `show` renderizam templates inexistentes → `MissingTemplate`. `pub/views` só tem `base`, `console`, `contracts`, `start`, `users` | Verificado por varredura do diretório. No ai9 esses paths viram **rotas reais de tela** (D-92) |
| **BE-309** | Feature inexistente: `structured_operation_taxes` tem 8 rotas geradas e **zero** controller, model, view, migration e tabela | As **únicas** 2 ocorrências da string no repositório são as linhas 107-108 de `config/routes.rb`. "Taxas por operação estruturada" seria **feature nova**, não portabilidade |
| **DB-291** | Par do BE-309 no nível de dados: nenhuma migration cria, nenhum model referencia, **zero linhas** | Varredura exaustiva do repositório |
| **OPS-280** | Par do BE-309 no nível de rota: 8 rotas, 0 código, nenhum link ou JS apontando para elas | idem |
| **OPS-281** | Par do BE-289 no nível de operação: toda a navegação real passa por `ConsoleController#index`, que monta `@view_path` | idem |
| **OPS-282** | Mecanismo legado descartado, comportamento preservado: `Dev.ilike` interpolava fragmento SQL conforme o adapter em runtime (e em SQLite caía no ramo MySQL, errado) | O valor já ia por bind, então **não havia injeção**; o ganho é clareza e um banco só (DEC-05) |
| **FE-296** | Código morto: `update_values()` lê `#structured_operation_operation_value` e escreve em `#structured_operation_balance` — **campo que não existe no formulário**. jQuery casa com **zero elementos**: no-op silencioso. `hasError` é setado como `false` e nunca vira `true` | **Guarda um sinal**: a intenção original era `balance = capital`, que **conflita** com a regra do model (`balance = −|saldo inicial|`). É insumo direto da **Q-R3**; por isso a decisão **B-11** manda seguir o model — produção é a verdade |
| **DB-289** | `receivable_entries.resource_kind_id`: coluna existe e é permitida nos strong params, mas **não há campo no formulário, não há validação e nenhuma query a lê** — sempre NULL | **`dropped` condicionado**: `SELECT COUNT(*) FROM receivable_entries WHERE resource_kind_id IS NOT NULL` no dump antes de confirmar (T-D7). É o que sustenta a Q-R5 |

## Perguntas em aberto que afetam esta fatia

| # | Assunto | Default adotado | Muda número? |
| - | ------- | --------------- | ------------ |
| **Q-R3** | O `balance` da operação estruturada deveria evoluir? (D-73) | Replicar o reset; coluna documentada como decorativa | não |
| **Q-R17** | A remuneração é mesmo percentual flat, sem prazo? (D-72) | Replicar a fórmula exatamente, com golden. **Nada muda no valor cobrado** | não |
| **Q-R5** | `resource_kinds` é portado ou descartado? | Tabela e seed sim; **superfície bloqueada** até a contagem no dump | não |
| **Q-R16** | A taxa de remuneração aceita valor fora de 0–100? | **Replicar**: hoje 250% passa. Validar a faixa recusaria registro que o sistema aceita | não |
| **Q-R7** | Validar `due_date >= issue_date` e `operation_value > 0`? | Replicar as ausências | não |
| **Q-R10** | Datas de operação existente são editáveis? | Não — regra de servidor, alinhada com S7 | não |
| **Q-R13** | Trocar a empresa move a operação de projeto em silêncio? | Passa a exigir confirmação explícita: mudança de projeto vira operação nomeada, não efeito colateral | não |
| **Q-R14** | O que era "considerar no variável" (`is_on_variable`)? | Portar a coluna, **sem inventar consumidor** | não |
| **Q-R15** | Os 4 flags de `structured_operation_types` migram? | Migrar as colunas; nenhuma delas ganha consumidor | não |
| **Q-R18** | Operação encerrada continua candidata a cobrança? | Sim — replicar | não |
| **Q-R19** | `is_active` de `resource_sources` passa a filtrar? | **Não.** Passar a filtrar faria fonte "desativada" sumir do select de recebíveis | não |
| **Q-R20** | O detalhe deve exibir os saldos com `.abs`? | Não — replicar o sinal negativo (DEC-01) | não |
| **Q-R21** | O que acontece ao editar remuneração cujo tipo foi desativado? | O select passa a conseguir exibir o tipo selecionado mesmo inativo, sem oferecê-lo para novos | não |
| **Q-R22** | `resource_kinds` e `resource_sources` têm o **mesmo** rótulo de menu e título de aba | Se as duas sobreviverem (Q-R5), precisam de nomes distintos | não |
| **Q-R9** | Os 13 textos de ajuda do formulário são placeholder | Portar o mecanismo; conteúdo em branco | não |
| **Q-R12** | A busca não procura por `contract_number` nem por empresa | Replicar o alcance atual | não |


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-561 | build | `resource_kinds` — tabela + seed | S8 é dona dos recursos da operação estruturada |
| DB-562 | build | `resource_sources` — tabela + seed (7 linhas) | idem |
| DB-580 | build | `structured_operation_types` — tabela + seed (4 linhas) | idem |
| DB-581 | build | `structured_operations` | idem |
| DB-582 | build | `remunerations` | idem |

**`DB-582` é onde o contrato C2 morde.** A remuneração é calculada em `float` no legado e o
alvo é `decimal(15,2)`: **float × decimal é a fonte de divergência de centavo**. O
`decimal(15,2)` do legado é preservado como `decimal(15,2)`, e a reconciliação do ETL trava
isso com o golden test da fórmula.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`FE-297` é de S8**, disputado com S7: a editabilidade das datas da operação
  **estruturada** é regra desta fatia. **`FE-260` é de S7** — a mesma pergunta para a
  operação de **risco** — e S8 apenas a cita: as duas adotam a mesma semântica (**Q-R10**),
  regra de servidor, datas não editáveis pela tela e a API aplicando o mesmo.
