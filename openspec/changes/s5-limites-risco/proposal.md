# Proposal: S5 — Limites de risco (`RiskControl`) e o motor de exposição

## Why

`RiskControl` é o teto que autoriza toda operação de crédito do Safegold: **nenhuma
operação de risco e nenhum recebível existem sem um limite cadastrado** para a combinação
(projeto, empresa, portador, tipo). E o motor de exposição construído sobre ele é o painel
principal do produto — a tela que o cliente abre para saber quanto de cada limite está
utilizado, disponível, liquidável e em pré-faturamento numa data.

A base ai9 pós-trim **não tem nada disso**: 18 models, nenhum financeiro. Não existe
`RiskControl`, `RiskOperationType`, `RiskOperation` nem equivalente próximo
(`.migration-ai9/map/risk-indicators.md` §0.1). O domínio inteiro é `build`; o reuso real
está na infra (paginação, `ApiResponseHandler`, Grape, design system, React Query) e está
citado arquivo a arquivo em cada linha do mapa.

Três coisas fazem esta fatia existir **antes** de S6 e S7:

1. **A forma do `RiskControl` mudou em 2022 e a descrição antiga circulou errada.**
   Verificado na fonte: `../sfg/db/migrate/20210510211438_create_risk_controls.rb` cria as
   8 colunas fixas (`limite_auto_liquidaveis`/`taxa_auto_liquidaveis`, `limite_fomento`/…,
   `limite_comissaria`/…, `limite_intercompany`/…) e
   `../sfg/db/migrate/20220611152145_change_risk_control_fields.rb` acrescenta
   `risk_operation_type_id`, `user_id`, `limite`, `taxa`, `original_balance` e
   `original_balance_pre`. **Hoje o `RiskControl` é uma linha por (empresa, portador,
   tipo)**, com **um** `limite` e **uma** `taxa`; as 4 modalidades viraram linhas de
   `RiskOperationType`, que é **cadastro aberto**. Quem modelar as 8 colunas fixas perde o
   `has_pre_faturamento`, os subtipos e **todo o motor de pré-faturamento**. Correção
   registrada no mapa como **C-09**.
2. **Contrato C2 — um serviço de cálculo, chamado pela tela E pela gravação.**
   `Risk::Calculator` é a única implementação das fórmulas de exposição. A prévia em tempo
   real do console chama **o mesmo serviço** que grava — é a única forma de prévia e
   gravação nunca divergirem (**D-09**).
3. **O legado não tem nenhum teste (D-114).** Replicar a convenção de sinal (**DEC-01**) e
   a aritmética em float (**DEC-02**) — as duas melhorias **DECLINADAS** pelo usuário — só é
   honesto se for verificável. Cada fórmula ganha um **golden test** com valores extraídos
   do legado. É o que transforma "replicar o float" de intenção em contrato verificável.

## What Changes

Entrega ponta a ponta as sub-fatias **R1, R2, R3, R4** do mapa de bloco
(`.migration-ai9/map/risk-indicators.md` §1) e deixa **R8** (posições diárias) bloqueada por
decisão, com o dado preservado:

- **R1 — esquema e catálogos.** As 7 tabelas de risco nascem com FK, índice e boolean
  (nenhuma das 7 do legado declara um único índice ou FK). Tipos de limite, subtipos e
  tipos de movimento viram CRUD real, com `integration_key` estável — fim da resolução por
  título literal.
- **R2 — limites.** CRUD, ativar/desativar, cascata empresa→portador, o `after_create` que
  abre o par estático pré/antecipação, e a tela "Limites".
- **R3 — motor de exposição.** As 8 fórmulas e os 2 payloads agregados em
  `Risk::Calculator` + `Risk::AggregateService`, travados por golden **antes** de qualquer
  tela consumir.
- **R4 — console "Controle de Risco".** Resumo por empresa/portador/data, os dois layouts
  (multi e portador único), semáforo de limite estourado e estado de erro — que hoje **não
  existe** (o `failure` do proxy legado é vazio).
- **R8 — posições diárias.** `risk_entries` ganha tabela e model (o dado sobrevive) e
  **nenhuma tela**, até a resposta de **Q-R4**.

**Não** entrega: operações de risco, movimentos, prorrogação e renovação (**S7**), nada de
`structured-operations` (**S8**) e nada de indicadores (**S10**). O esquema das tabelas
`risk_movements` (DB-236) e `risk_operation_extensions` (DB-237) nasce **aqui**, porque as
7 tabelas de risco são criadas juntas — S7 consome o esquema, não o cria.

### Dependências

| Direção | O quê |
| ------- | ----- |
| Consome de **S0** | `Project`, `Membership`, `current_project!`, `ProjectScoped`, papéis + hierarquia (C3), `user_is_readonly` |
| Consome de **S0/DS** | `DataTable`, `Pagination`, `MoneyInput`/`PercentInput`, `EmptyState`/`ErrorState`, `SearchableSelect` |
| Consome de **S3/S4** | `Carrier`, `CarrierGroup`, `Company`, `Project` |
| **Contribui** para a biblioteca | `DS/DateRangePicker.tsx` (modo single) — não existe na base e não está no S0; nasce aqui como membro compartilhado (Princípio 11) |
| Entrega para **S6** | contrato "recebível exige `RiskControl` ativo" (parte de OPS-238, cujo restante é de S7) |
| Entrega para **S7** | esquema das 7 tabelas, catálogos semeados, `Risk::Calculator` |
| Entrega para **`companies-carriers`** | `BE-251` (`total_limits_on`) é calculado aqui; o endpoint é exposto em `EP/companies.rb` |
| Entrega para **`receivables`** | `BE-052` (resumo de limites) consome R3 |

### Decisões que governam esta fatia

| Decisão | Efeito prático aqui |
| ------- | ------------------- |
| **DEC-01** (melhoria **declinada**, D-93) | Convenção de sinal replicada **exatamente**: `original_balance` negativo, débito `+1`/crédito `−1`, `limite_utilizado = Σ balance_on × (−1)`. **QA não deve ler como regressão** — está em `improvements-log.md` |
| **DEC-02** (melhoria **declinada**, D-104) | O `.to_f` de `limite_disponivel_on` e de `perc_limite_utilizado_on` é replicado. Golden trava o centavo |
| **C1** | Escopo por projeto **no endpoint**, via `current_project!`. Nunca `default_scope`. Catálogos (`risk_operation_types`, `risk_movement_types`) são **globais**, sem escopo |
| **C2** | `Risk::Calculator` é chamado pela prévia da tela **e** pela gravação. Nunca duas implementações |
| **C3** | Hierarquia do ai9 (**menor = mais poder**); todo teste de autorização verifica **os dois lados** |
| **DEC-09** | Nada é inventado. Sem gráfico (§0.3), sem alerta em tempo real (§0.4), sem export (OPS-239) |
| **Princípio 6b** | O que parecer errado na base ai9 e não bloquear vira linha em `upstream-flags.md` |

## Impact

- **Afetado:** `backend/db/migrate` + `schema.rb`, `backend/app/models/risk_*.rb`,
  `backend/app/services/risk/`, `backend/app/controllers/api/v1/risk_*.rb` e
  `api/entities/`, `backend/db/seeds/`, `frontend/src/features/risk/`,
  `frontend/src/components/ui/` (3 membros novos da biblioteca), `useNavItems.ts`.
- **Não afetado:** o legado `sfg` (read-only) e tudo o que S7/S8/S10 constroem.
- **Mudanças visíveis** (registrar em `improvements-log.md` para o QA não abrir bug):
  **IMP-R3** — o parâmetro `q` da busca de limites passa a filtrar de verdade (hoje é lido e
  nunca aplicado, e a mensagem de "busca sem resultado" nunca aparecia).
- **Risco principal:** "otimizar" o agregado e mudar o número. Os agregados fazem N+1
  explícito (limites × operações × query de movimento por data) e, com float na cadeia, a
  **ordem da soma muda centavos** (decisão **B-07**). Mitigação: golden roda **antes** e
  depois de qualquer índice ou `preload`.

## IDs de inventário cobertos (66)

Estratégia copiada de `.migration-ai9/map/risk-indicators.md` §2.1, §2.2 e §2.3.
**Placar: 58 `build` · 4 `build?` · 3 `drop` · 1 `reuse`.**

### `risk` — catálogos, esquema e limites (mapa §2.1, R1 + R2)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| DB-230 | build | `MIG/*_limites_de_risco_nascem_com_integridade.rb` — único em (company, carrier, type) |
| DB-232 | build | `MIG/*_tipos_de_limite.rb` — único em `title` e `integration_key` |
| DB-233 | build | `MIG/*_subtipos_de_limite.rb` — `pair_id` FK auto-referente |
| DB-234 | build | `MIG/*_tipos_de_movimentacao_de_risco.rb` — `credit_type` check `('C','D')` |
| DB-236 | build | `MIG/*_movimentos_de_risco.rb` — índice (op, `date`, `created_at`); `order` → `sequence` |
| DB-237 | build | `MIG/*_prorrogacoes_de_operacao.rb` — FK cascade + check `new_due_date > original_due_date` |
| DB-238 | build | as 7 migrations: nenhuma das 7 tabelas legadas tem índice ou FK |
| DB-240 | **build?** | **Q-R4/dump** — as 8 colunas pré-2022 só saem se não houver linha com `risk_operation_type_id IS NULL`. Ver "Como cada `build?` foi resolvido" |
| BE-278 | build | `MOD/risk_operation_type.rb`, `MOD/risk_operation_subtype.rb`; `SVC/risk/operation_type_service.rb`; `EP/risk_operation_types.rb` |
| BE-279 | build | `MOD/risk_movement_type.rb`; `SVC/risk/movement_type_service.rb`; `EP/risk_movement_types.rb` |
| FE-277 | build | `FE/risk/pages/OperationTypesPage.tsx` |
| FE-278 | build | `FE/risk/pages/MovementTypesPage.tsx` |
| OPS-230 | build | `db/seeds/risk_operation_types.rb` — 4 tipos, idempotente por `integration_key` |
| OPS-231 | build | `db/seeds/risk_movement_types.rb` — 8 tipos, idempotente por `integration_key` |
| OPS-232 | build | `MOD/risk_movement_type.rb` scopes `.release`, `.transfer_out`, `.transfer_in` (decisão **B-09**) |
| OPS-233 | build | `MOD/risk_operation.rb#is_static` + predicado `(is_static OR janela)` (decisão **B-08**) |
| OPS-234 | **drop** | `Dev.ilike` morre; entra `ILIKE` nativo do Postgres (DEC-05) |
| OPS-236 | **build?** | **dump** — `generate_new_controls_on_migration`. Ver "Como cada `build?` foi resolvido" |
| BE-230 | build | `SVC/risk/control_service.rb#index`; `EP/risk_controls.rb` — **IMP-R3** |
| BE-232 | build | `…#carriers_for_company`, `#controls_filter` |
| BE-233 | build | `EP/risk_controls.rb` — `new`/`edit` viram estado de tela (drawer) |
| BE-234 | build | `…#create` — transação em volta do `after_create` de BE-241 |
| BE-235 | build | `…#update` — empresa/portador/tipo imutáveis no servidor (decisão **B-01**) |
| BE-236 | build | `…#activate` — `save!` |
| BE-237 | build | `…#deactivate` — **duas leituras divergentes replicadas** (decisão **B-02**) |
| BE-238 | build | `…#destroy` — 422 em vez de 202 (família D-24/D-98) |
| BE-239 | build | `MOD/risk_control.rb` `before_validation` (título, projeto, `has_safegold_management`) |
| BE-240 | build | `MOD/risk_control.rb` `validates` — unicidade da quádrupla; limite zero continua válido |
| BE-241 | build | `MOD/risk_control.rb` `after_create` + `SVC/risk/static_pair_service.rb` |
| BE-252 | build | `…#available_for_entry_on` |
| FE-240 | build | `FE/risk/pages/RiskControlsPage.tsx` |
| FE-241 | build | `FE/risk/components/RiskControlFilters.tsx` — portadores do projeto, não `Carrier.all` |
| FE-242 | build | `DS/Pagination.tsx` (**membro novo da biblioteca**) |
| FE-243 | build | `FE/risk/components/RiskControlRow.tsx` — rótulo "Legado" condicionado a DB-240 |
| FE-244 | build | `FE/risk/components/RiskControlDrawer.tsx` |
| FE-245 | build | `FE/risk/components/InitialBalanceFields.tsx` |
| FE-246 | build | `DS/MoneyInput.tsx`, `DS/PercentInput.tsx`, `lib/format/money.ts` (**compartilhados**) |
| FE-247 | build | `FE/risk/components/RiskControlActions.tsx` |
| FE-248 | build | guardas de empresa/portador + gate de servidor |
| FE-249 | build | `DS/EmptyState.tsx`, `DS/ErrorState.tsx` (**compartilhados**) |

### `risk` — motor de exposição (mapa §2.2, R3) · **zona DEC-01**

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-242 | build | `SVC/risk/calculator.rb#operations_on` |
| BE-243 | build | `…#limite_utilizado_on` — `Σ balance_on × (−1)`. **Replicar** |
| BE-244 | build | `…#limite_liquidavel_on` |
| BE-245 | build | `…#limite_pre_on` |
| BE-246 | build | `…#limite_disponivel_on` — `(limite − utilizado).to_f`. **DEC-02** |
| BE-247 | build | `…#vencidos_on` — sem inversão de sinal; domínio sem endpoint (decisão **B-12**) |
| BE-248 | build | `…#a_vencer_on` — idem |
| BE-249 | build | `SVC/risk/aggregate_service.rb` — `Company` e `Project` viram **um** service parametrizado |
| BE-250 | build | `…#controls_info_on` — **os dois bugs de rótulo do D-95 replicados** (DEC-01) |
| BE-251 | build | `…#total_limits_on`; endpoint em `EP/companies.rb` (bloco `companies-carriers`) |
| BE-231 | build | `…#summary_on`; `EP/risk_controls.rb#summary` — o payload do console |
| BE-266 | build | `MOD/risk_operation.rb#balance_on` — **sem movimento devolve 0, não `original_balance`** |

### `risk` — console, posições diárias e transversais (mapa §2.3, R4 + R8)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| FE-230 | build | `FE/risk/pages/RiskConsolePage.tsx` + item de menu em `useNavItems.ts` |
| FE-231 | build | `FE/risk/components/RiskConsoleFilters.tsx` — empresa, opção "Grupo econômico" |
| FE-232 | build | idem — portadores com limite ativo, opção "TODOS" |
| FE-233 | build | `DS/DateRangePicker.tsx` modo single, `maxDate = hoje`. **Replicar** |
| FE-235 | build | `FE/risk/components/ExposureByTypeTable.tsx` — herda os erros de BE-250 |
| FE-236 | build | `FE/risk/components/ExposureSingleCarrier.tsx` |
| FE-237 | **reuse** | `frontend/src/components/ui/accordion.tsx` (Radix) — serve como está |
| FE-238 | build | `DS/tokens` — par único `--indicator-positive`/`--indicator-negative` (decisão **B-10**, D-101) |
| FE-239 | build | estados de erro e vazio do console — hoje **não existem** |
| FE-279 | adapt | policy do bloco **AUTH.S3** aplicada a `EP/risk_*.rb` (corrige D-23/D-34) |
| BE-269 | **build?** | **Q-R4** — `MOD/risk_entry.rb` + regras derivadas, **sem tela** |
| DB-231 | **build?** | **Q-R4** — `MIG/*_posicoes_diarias_de_risco.rb` |
| FE-234 | **drop** | botão "Cadastrar posição" — nasce `deactive`, escondido no boot, bloco comentado |
| OPS-239 | **drop** | não existe export PDF/CSV em módulo nenhum do legado |

## Como cada `build?` foi resolvido (4)

| ID | Pergunta | Resolução nesta fatia |
| -- | -------- | --------------------- |
| **DB-240** | As 8 colunas pré-2022 podem ser descartadas? | **Não decidido aqui.** A migration nasce **com** as 8 colunas preservadas e o rótulo "Legado" (FE-243) ativo. O descarte vira tarefa do ETL (S14), destravada pela contagem `SELECT count(*) FROM risk_controls WHERE risk_operation_type_id IS NULL` no dump. Tarefa de decisão **T-D1** |
| **OPS-236** | Portar `generate_new_controls_on_migration`? | **Não construir agora.** A rotina só existe se DB-240 revelar linhas legadas. Registrada como pendência do ETL; se for necessária, nasce **idempotente** e **não apaga `risk_entries`** sem a resposta de Q-R4. Tarefa de decisão **T-D1** (mesma contagem) |
| **BE-269** | `RiskEntry` volta a ter tela? | **Dado sim, tela não.** Model + validações + totais derivados portados e cobertos por teste; **nenhum endpoint e nenhuma tela**. Tarefa de decisão **T-D2** (Q-R4) |
| **DB-231** | A tabela `risk_entries` é criada? | **Sim.** A tabela tem dado em produção; não criá-la é perda. Nasce com o único (`date`, `risk_control_id`, `company_id`). A remodelagem por tipo (que os 15 campos hardcoded exigiriam) é **feature nova** e não é feita. Tarefa de decisão **T-D2** |

## `drop` — motivo registrado (3)

Cada um vira linha `dropped` no `parity-ledger.md` **com a evidência**, nunca por omissão.

| ID | Motivo | Evidência |
| -- | ------ | --------- |
| **OPS-234** | Mecanismo legado descartado, comportamento preservado. `Dev.ilike` escolhia fragmento SQL por adapter em runtime; o ai9 é Postgres fixo (DEC-05) | `../sfg/config/initializers/dev.rb:3-5`. O requisito de busca insensível a maiúsculas continua vivo — muda a implementação, não o comportamento |
| **FE-234** | Código morto: o botão "Cadastrar posição diária" nasce com classe `deactive`, é escondido no boot e **todo o bloco que o exibiria está comentado** | `../sfg/…/risk/_body.html.erb:22-25`; `_body.js.erb:125-136,:164`. **Condicionado a Q-R4**: se a posição diária voltar, o botão volta junto |
| **OPS-239** | Nada a portar: **não existe nenhuma exportação PDF ou CSV** no módulo de risco — nem em módulo nenhum do legado | Varredura por geradores de PDF/planilha em `../sfg/app/`: a única ocorrência de "wicked_pdf" no repositório está dentro de um binário de imagem. Export continua fora por DEC-09 |

## Perguntas em aberto que afetam esta fatia

Todas com default declarado no mapa §5; nenhuma bloqueia o início de R1, R2, R3 ou R4.

| # | Assunto | Default adotado | Muda número? |
| - | ------- | --------------- | ------------ |
| **Q-R4** | A posição diária de risco (`RiskEntry`) volta? (D-99) | Tabela e model portados, **sem tela**. R8 fica bloqueada | não |
| **DB-240/dump** | Existem limites pré-2022 sem tipo? | Colunas preservadas, rótulo "Legado" ativo, descarte adiado para o ETL | **sim, se houver** — linhas sem tipo somem de todos os agregados |
| **Q-R2** | Alerta de estouro de limite em tempo real | **Não fazer.** O legado não faz polling em nenhuma tela deste bloco; seria feature nova (DEC-09) | não |
| **Q-R1** | A grade de indicadores ganha gráfico? | Não é desta fatia; registrada em S10 | não |
| **Q-R9** | Os textos de ajuda dos formulários são placeholder no legado | Portar o **mecanismo**, conteúdo em branco | não |
| **C-07** | Kaminari está no Gemfile **sem nenhum uso** em `backend/app` | Escolher **um** padrão de paginação no S0 e segui-lo nos 14 endpoints do bloco. Não pode ficar meio a meio | não |


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-572 | build | `risk_controls` visto por `data-schema` — **uma linha por (empresa, portador, tipo)**, a forma pós-2022 | S5 é dona de `RiskControl` |
| DB-573 | build | `risk_entries` | idem |
| DB-574 | build | `risk_operation_types` — tabela + **seed ativo de produção** (as modalidades viraram cadastro aberto em 2022) | idem |
| DB-575 | build | `risk_operation_subtypes` | idem |

**Estes quatro são as mesmas tabelas que a fatia já constrói**, vistas pelo inventário de
`data-schema`. O que eles acrescentam é o lembrete que o mapa registrou como achado nº 3:
`RiskControl` **mudou de forma em 2022** (`20220611152145_change_risk_control_fields`) —
deixou de ser 4 modalidades em colunas fixas e passou a ser uma linha por
(empresa, portador, tipo). O ETL precisa ler **os dois formatos**.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`DB-236` e `DB-237` são de S5** — disputados com S7. As migrations de `risk_movements` e
  `risk_operation_extensions` nascem **aqui**, junto do resto do esquema de risco, porque as
  FKs precisam existir antes de S7 escrever a operação. **S7 consome**: constrói o
  comportamento de movimento e prorrogação sobre estas tabelas.
- **`FE-234`, `OPS-234` e `OPS-239` são de S5** — os 3 `drop` da capability `risk`, com a
  evidência registrada nesta fatia. S7 não descarta nada por omissão e apenas os nomeia.
- **`BE-243`, `BE-249`, `BE-251` e `FE-238` são de S5** — disputados com S15. O
  `Risk::Calculator`, o `AggregateService` e o par de tokens do semáforo de limite nascem
  aqui, com o golden test do contrato **C2**. **S15 consome**: o dashboard lê o mesmo serviço
  que a tela de risco, e **não** soma nada no cliente.
