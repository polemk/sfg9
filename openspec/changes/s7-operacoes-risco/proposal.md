# Proposal: S7 — Operações de risco: movimentos, prorrogação e renovação

## Why

A operação de risco é onde o limite vira dinheiro. Ela consome o `RiskControl` de S5, é
criada manualmente **ou** pelo borderô de S6, e carrega a única cadeia de saldos do
Safegold: cada movimento reescreve o saldo de todos os movimentos seguintes, e o
`risk_operations.balance` é um **cache derivado** reescrito no `before_validation` de todo
save.

Esta fatia existe porque três coisas só acontecem aqui:

1. **A cadeia de saldos (C2).** `Risk::Calculator#recalculate_chain` é a única
   implementação do algoritmo `balance_n = balance_{n-1} + sinal × movement_value`. A tela
   de extrato, o cartão "última movimentação" e a gravação passam **pelo mesmo serviço** —
   é o que impede a tela de mostrar um número e o extrato outro (**D-09**). Cada regra
   ganha **golden test** com valores extraídos do legado, que **não tem nenhum teste**
   (**D-114**).
2. **Duas das cinco IDORs da família D-01/D-16/D-29/D-76/D-100 são desta fatia.**
   `risk_operations#search` (BE-253) e a listagem de movimentos (BE-270) **descartam o
   escopo de projeto** quando recebem um parâmetro de id — vazam operação de qualquer
   projeto para qualquer autenticado. Com o escopo explícito no endpoint (**C1**), esse
   erro fica visível na revisão em vez de invisível em produção.
3. **Um defeito que quebra em produção hoje.** `RiskMovement`'s `after_commit` faz
   `on_duplicate_key_update: [:date, movement_value]` — **`movement_value` está sem os
   dois-pontos**, é variável local inexistente: editar um movimento de transferência
   levanta `NameError` em produção (**D-97**). A transferência pré↔antecipação está
   quebrada no legado.

## What Changes

Entrega ponta a ponta as sub-fatias **R5, R6 e R7** do mapa de bloco
(`.migration-ai9/map/risk-indicators.md` §1):

- **R5 — operações de risco: lista, formulário, detalhe.** CRUD com escopo de projeto
  fechado (D-100), paginação e total reais, ordenação multi-coluna com allowlist no
  servidor e a cascata de 5 callbacks de criação.
- **R6 — movimentos e cadeia de saldos + transferência pré↔antecipação.** Extrato,
  recálculo em cascata, espelhamento do par (hoje quebrado por `NameError`) e o cartão
  "última movimentação" — que hoje dá **500 na abertura do detalhe** de qualquer operação
  sem movimento, caso real das estáticas recém-criadas.
- **R7 — prorrogação e renovação.** Log imutável de vencimento e renovação encadeada.
  Aqui mora o **D-94**: renovar passa a **encerrar a original**, que hoje continua viva e
  faz a mesma exposição ser contada em dobro.

**Não** entrega: o esquema das tabelas de risco, os catálogos, os limites e o motor de
exposição (**S5**); nada de `structured-operations` (**S8**) nem de indicadores (**S10**).
As migrations de `risk_movements` e de `risk_operation_extensions` (IDs de **S5**) nascem em
S5, junto com as outras 5 tabelas de risco — esta fatia **consome** o esquema.

### Dependências

| Direção | O quê |
| ------- | ----- |
| Consome de **S5** | as 7 tabelas, os catálogos semeados com `integration_key` de contrato, `Risk::Calculator#balance_on`, `RiskControl`, `is_static`, `Risk::StaticPairService` |
| Consome de **S6** | `ReceivableEntry` — a integração recebível → operação/movimento é **implementada lá**, com o contrato definido aqui (OPS-238) |
| Consome de **S0/DS** | `DataTable` (ordenação multi-coluna tri-state), `Pagination`, `MoneyInput`, `EmptyState`/`ErrorState`, `DateRangePicker` (contribuído por S5) |
| Entrega para **S6** | `SR-5`/`SR-6` dependem de `R5`/`R6`: sem a operação e o movimento, o borderô não fecha |
| Entrega para **S8** | `RiskOperation` como `operation_class` das remunerações da classe **LIQ** (BE-304/BE-306) |
| Entrega para **S13** | nada de job agendado — o legado não tem nenhum neste domínio |

### Decisões que governam esta fatia

| Decisão | Efeito prático aqui |
| ------- | ------------------- |
| **DEC-01** (melhoria **declinada**, D-93) | `original_balance = -(|original_balance|)` em **todo** save; crédito `−1`, débito `+1`; saldo inicial exibido positivo no formulário e negativo no detalhe. **QA não deve ler como regressão** |
| **DEC-02** (melhoria **declinada**, D-104) | A aritmética da cadeia é replicada como está. Golden trava o centavo |
| **C1** | Escopo por projeto **no endpoint**. `risk_operation_id` deixa de substituir a relation inteira |
| **C2** | `Risk::Calculator#recalculate_chain` é chamado pela leitura do extrato **e** pela gravação. Uma implementação só |
| **C3** | Hierarquia do ai9; todo teste de autorização verifica **os dois lados** |
| **D-94** (corrigir — **fora** do alcance do DEC-01) | Renovar **encerra** a original. Mudança observável: **IMP-R1** |
| **Princípio 9** | Performance sem alterar resultado: índice + um único `upsert_all`. Reordenar por `id` **muda saldo** |
| **Princípio 6b** | O que parecer errado na base ai9 e não bloquear vira linha em `upstream-flags.md` |

## Impact

- **Afetado:** `backend/app/models/{risk_operation,risk_movement,risk_operation_extension}.rb`,
  `backend/app/services/risk/{operation_service,movement_service,transfer_service,renewal_service,extension_service,calculator}.rb`,
  `backend/app/controllers/api/v1/risk_operations.rb` + entities,
  `backend/db/migrate` (só `DB-235`, a tabela `risk_operations`),
  `frontend/src/features/risk/`, `useNavItems.ts`.
- **Não afetado:** o legado `sfg` (read-only); tudo o que S5 já entregou.
- **Mudanças visíveis** (registrar em `improvements-log.md`):
  **IMP-R1** — renovar passa a encerrar a operação original, e a exposição deixa de ser
  contada em dobro enquanto as janelas se sobrepõem. **Números do painel mudam, de
  propósito** (D-94).
- **Risco principal:** a cadeia de saldos. `recalculate_chain` roda no `before_validation`
  de **todo** save da operação e persiste pulando validações. Qualquer mudança na ordenação
  (`date asc, created_at asc`), na reatribuição de `sequence` a partir de 1 ou no ponto em
  que a validação de janela **não** é reaplicada muda o saldo que a tela e o extrato
  mostram.

## IDs de inventário cobertos (55)

Estratégia copiada de `.migration-ai9/map/risk-indicators.md` §2.1 (só `OPS-235`) e §2.3.
**Placar: 52 `build` · 3 `build?` · 0 `drop` · 0 `adapt` de descarte** (2 `adapt` são
contratos entre blocos).

> **Desvio de empacotamento declarado:** `OPS-235` está listado na fatia **R1** do mapa
> (§1), mas descreve a persistência da cadeia de saldos (`upsert_all` em
> `SVC/risk/calculator.rb`), que só existe com `BE-265`. Ele foi movido para **S7**. É o
> único ID do bloco que muda de fatia em relação ao mapa; nenhum outro foi reagrupado.

### `risk` — operações: CRUD, model e dados (mapa §2.3, R5)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| DB-235 | build | `MIG/*_operacoes_de_risco.rb` — índices, FKs, `is_static`, `original_balance` com sinal preservado |
| BE-253 | build | `SVC/risk/operation_service.rb#index`; `EP/risk_operations.rb` — **corrige D-100 (IDOR)** |
| BE-254 | build | `…#filter_options` — cascata empresa↔portador↔tipo manual |
| BE-255 | build | `…#last_movement` — payload vazio em vez de **500** quando não há movimento |
| BE-256 | build | `…#create` — transação em volta da cadeia BE-261→BE-262→BE-263→BE-264→BE-265 |
| BE-257 | build | `…#update` — um save, um recálculo (decisão **B-03**) |
| BE-258 | build | `…#destroy` — 422 real; hoje é literalmente `errors.any? ? :ok : :ok` (D-98) |
| BE-261 | build | `MOD/risk_operation.rb` — resolve `RiskControl` pela quádrupla, **sem filtrar `is_active`** |
| BE-262 | **build?** | `MOD/risk_operation.rb` — tipo↔subtipo. **Q-R6**, ver "Como cada `build?` foi resolvido" |
| BE-263 | build | `MOD/risk_operation.rb` — `original_balance = -(|original_balance|)`. **DEC-01** |
| BE-264 | build | `MOD/risk_operation.rb` `after_create` — movimento "Liberação do Recurso" só para tipo **sem** pré |
| BE-267 | build | `MOD/risk_operation.rb` `validates` — **replicar as ausências** (sem `due_date >= issue_date`, sem `operation_value > 0`) |
| BE-268 | **build?** | `MOD/risk_operation.rb` — estado de `is_ended`. **Q-R8**, ver "Como cada `build?` foi resolvido" |
| FE-250 | build | `FE/risk/pages/RiskOperationsPage.tsx` — a coluna "Tipo" mostra o **subtipo** |
| FE-251 | build | `FE/risk/components/RiskOperationSearch.tsx` — um campo, debounce 300 ms |
| FE-252 | build | `FE/risk/components/RiskOperationFilters.tsx` — filtro usa `.all`, cadastro usa `.active` (decisão **B-04**) |
| FE-253 | build | `DS/DateRangePicker.tsx` modo range — corrige o bug do rótulo de ano |
| FE-254 | build | `DS/DataTable.tsx` — ordenação multi-coluna tri-state, allowlist espelhada no servidor |
| FE-255 | build | paginação da lista, default 50 |
| FE-256 | build | `FE/risk/components/RiskOperationRow.tsx` — Renovar/Prorrogar só para tipo sem pré |
| FE-257 | build | guardas `carrier_available` + `manual_control`, espelhadas no servidor |
| FE-258 | build | `FE/risk/components/RiskOperationForm.tsx` — cascata empresa → portador → tipo |
| FE-259 | build | idem — blocos Cadastro / Datas / Valores / Taxa Acordada / Outros |
| FE-260 | **build?** | idem — datas na edição. **Q-R10**, ver "Como cada `build?` foi resolvido" |
| FE-261 | build | barra de ação inferior dizendo **o que falta**, em vez de o botão sumir |
| FE-262 | build | `DS/MoneyInput.tsx`/`DS/PercentInput.tsx` no formulário |
| FE-263 | build | `DS/EmptyState.tsx` — bloqueios "sem portador com limite manual" e "sem empresa" |
| FE-264 | build | `FE/risk/pages/RiskOperationDetailPage.tsx` — abas GERAL / MOVIMENTAÇÕES / PRORROGAÇÕES |
| FE-265 | build | `FE/risk/components/OperationGeneralTab.tsx` — **saldo inicial exibido negativo** (DEC-01) |
| FE-268 | build | chips "Recebível" e "Operação Original" como `<Link>` reais (D-92) |
| OPS-237 | build | textos de ajuda carregados **uma vez**, não `YAML.load_file` a cada render |

### `risk` — movimentos e cadeia de saldos (mapa §2.3, R6)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-265 | build | `SVC/risk/calculator.rb#recalculate_chain` — **o coração da fatia**. DEC-01 + DEC-02 |
| OPS-235 | build | persistência da cadeia por `upsert_all` (Rails 8) — `activerecord-import` **não existe** no Gemfile |
| BE-270 | build | `SVC/risk/movement_service.rb#index` — paginação **e** escopo de projeto (hoje não há nenhum dos dois) |
| BE-271 | build | `…` helpers de movimento novo e de transferência |
| BE-272 | build | `…#create` — `company_id`/`carrier_id`/`project_id` copiados da operação; `movement_value > 0` no servidor (decisão **B-05**) |
| BE-273 | build | `…#update`, `#destroy` — `after_destroy` refaz a cadeia e o `sequence` |
| BE-274 | build | `MOD/risk_movement.rb` — janela de datas fechada nas duas pontas; nunca dispara para operação estática |
| BE-275 | build | `SVC/risk/transfer_service.rb` — contrapartida na `pair_operation`, **validada antes**, em transação |
| BE-276 | build | `after_commit` do movimento — **corrige D-97** (`NameError` em produção) e a exclusão do par |
| FE-266 | build | `FE/risk/components/LastMovementCard.tsx` — tokens semânticos (D-101) |
| FE-269 | build | `FE/risk/components/MovementsTab.tsx` — sequência, Data, Tipo, Valor, Saldo, Observação, menu |
| FE-270 | build | `FE/risk/components/MovementRow.tsx` — `R$ 1.234,56C` / `…D`, sufixo **replicado** |
| FE-271 | build | `FE/risk/components/MovementDrawer.tsx` — datepicker alinhado ao servidor (fim do off-by-one) |
| FE-272 | build | botão "Transferir" só para operação de subtipo pré-faturamento |
| FE-273 | build | confirmação + recarga da lista e do cartão |
| FE-276 | build | estados vazio e de **erro** nas listas de movimentos e prorrogações |

### `risk` — prorrogação e renovação (mapa §2.3, R7)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-259 | build | `SVC/risk/renewal_service.rb#prepare` — preserva o prazo em dias |
| BE-260 | build | `…#create` — **D-94: a renovação encerra a original** (IMP-R1) |
| BE-277 | build | `SVC/risk/extension_service.rb` — log imutável de vencimento, `new_due_date > original_due_date` |
| FE-267 | build | `FE/risk/components/RenewalsCard.tsx` — cadeia por `original_id` com o estado de cada elo |
| FE-274 | build | `FE/risk/components/ExtensionDrawer.tsx` |
| FE-275 | build | `FE/risk/components/RenewalDrawer.tsx` — `minDate`/`maxDate` que hoje não existem |

### Contratos entre blocos (mapa §2.3)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| DB-239 | adapt | contrato de FK/escopos entre `risk_operations`, `receivable_entries` e `receipts`. **Donas: `receivables` e `charges`** — esta fatia fornece a regra e o teste de integração |
| OPS-238 | adapt | `SVC/risk/receivable_integration_service.rb` (contrato) — implementação no bloco `receivables` (**S6**) |

## Como cada `build?` foi resolvido (3)

> Dois deles são **conflitos entre o mapa e a spec aprovada**. Onde os dois divergem, esta
> fatia segue a **spec** — ela é o requirement aprovado no Phase 1 — e leva a divergência ao
> usuário como tarefa de decisão. Isso está explícito aqui para ninguém "corrigir" de volta.

| ID | Pergunta | Resolução nesta fatia |
| -- | -------- | --------------------- |
| **BE-262** | Para tipo com pré-faturamento, qual subtipo é o padrão quando o formulário não manda? (**Q-R6**) | **Conflito mapa × spec.** O mapa manda replicar ("o primeiro subtipo", ordem de inserção); `openspec/specs/risk/spec.md` → `BE-262` já resolve pedindo **escolha explícita do subtipo**. Adotada a **spec**: gravação recusada com 422 quando o tipo tem pré e nenhum subtipo veio. Tarefa de decisão **T-D3** confirma. Efeito: fecha a escolha arbitrária que decide em qual bucket (liquidável × pré) a operação entra |
| **BE-268** | "Encerrar" bloqueia movimento e prorrogação? (**Q-R8**) | **Conflito mapa × spec.** O mapa propõe bloquear (D-94); a spec (`BE-268`) diz que a operação encerrada **continua na janela, continua consumindo limite e continua aceitando movimentos**, por DEC-01. Adotada a **spec**: `is_ended` continua rótulo, sem efeito colateral. Modelado como `enum` string + service (não `aasm`, que está no Gemfile sem uso). Tarefa de decisão **T-D4**. **Em nenhuma hipótese** a operação encerrada sai de `operations_on` sem assinatura do usuário — isso mudaria a exposição do histórico inteiro |
| **FE-260** | As datas de operação existente deveriam ser editáveis? (**Q-R10**) | **Regra de servidor.** A spec da operação estruturada (**S8**) já resolve assim — "as datas não são editáveis pela tela, **e a API aplica a mesma regra**" — e manter duas semânticas para a mesma pergunta em dois módulos irmãos é pior que qualquer uma das duas. Adotado o mesmo em risco, somado à decisão **B-03** (encolher a janela deixando movimentos fora é recusado). Tarefa de decisão **T-D5** |

## `drop` — nenhum nesta fatia

Esta fatia **não tem nenhum ID `drop`**. Os 3 `drop` da capability `risk` pertencem a
**S5**, com a evidência registrada lá e os IDs nomeados na seção "Fronteiras" abaixo. Nada é
descartado aqui por omissão.

## Perguntas em aberto que afetam esta fatia

| # | Assunto | Default adotado | Muda número? |
| - | ------- | --------------- | ------------ |
| **Q-R6** | Subtipo padrão em tipo com pré-faturamento | Recusar sem subtipo explícito (spec) | **sim** — decide o bucket liquidável × pré |
| **Q-R8** | Encerrar bloqueia movimento e prorrogação? | Não bloqueia (spec, DEC-01) | não |
| **Q-R10** | Datas de operação existente são editáveis? | Não, regra de servidor | não |
| **Q-R11** | Transferir a partir da antecipação gera contrapartida? | Não gera — só o sentido pré → antecipação espelha. Replicar | não |
| **Q-R7** | Validar `due_date >= issue_date` e `operation_value > 0`? | **Replicar as ausências** — não recusar dado que hoje entra | não |
| **Q-R9** | Os 13 textos de ajuda do formulário são placeholder no legado | Portar o **mecanismo**; conteúdo em branco até o negócio escrever | não |
| **BE-257/spec** | Alterar o capital deixa o movimento de liberação divergente | Replicar: o movimento existente permanece como está | não |


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-576 | build | `risk_operations` visto por `data-schema` | S7 é dona da operação de risco |
| DB-577 | build | `risk_operation_extensions` — FK em cascata + check `new_due_date > original_due_date` | S7 é dona das prorrogações |
| DB-578 | build | `risk_movement_types` — tabela + seed (8 linhas) | S7 é dona dos movimentos |
| DB-579 | build | `risk_movements` — índice em (operação, `date`, `created_at`); `order` vira `sequence` | idem |

**`DB-579` traz um requisito de ordem para o ETL:** o saldo depende da ordem, e a carga
**tem** de migrar em ordem de `sequence`. Migrar fora de ordem produz saldo plausível e
errado — a classe de erro que ninguém percebe.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`DB-236` e `DB-237` são de S5**, não desta fatia. As migrations de `risk_movements` e
  `risk_operation_extensions` nascem lá, com o resto do esquema de risco; S7 constrói o
  **comportamento** de movimento e prorrogação sobre elas.
- **`FE-234`, `OPS-234` e `OPS-239` são de S5** — os 3 `drop` da capability `risk`. A
  evidência está registrada lá; aqui não há descarte.
- **`FE-260` é de S7**, disputado com S8: a editabilidade das datas da **operação de risco**
  é regra desta fatia. **`FE-297` é de S8** — a mesma pergunta para a operação **estruturada**
  — e S7 apenas a cita, porque as duas fatias adotam a mesma semântica (**Q-R10**): as datas
  não são editáveis pela tela **e a API aplica a mesma regra**. Manter duas semânticas para a
  mesma pergunta em módulos irmãos seria pior que qualquer uma das duas.
- **`DB-576`, `DB-577`, `DB-578` e `DB-579` são de S7** (adotados no fechamento do Phase 2):
  operação, prorrogação, tipos de movimento e movimentos.
