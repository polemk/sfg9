# Design: S7 — Operações de risco, movimentos, prorrogação e renovação em ai9

> As 55 linhas item-a-item **não são duplicadas aqui**. A fonte é
> `.migration-ai9/map/risk-indicators.md` **§2.3** (operações, movimentos, prorrogação e
> renovação) mais `OPS-235`, que vem de **§2.1**. Cada linha lá traz "Equivalente ai9",
> "O que muda", "Melhoria proposta" e "Risco". Este documento descreve **o desenho**.

## 1. `Risk::Calculator#recalculate_chain` — o coração da fatia (C2)

### O algoritmo, medido na fonte

`../sfg/app/models/risk_operation.rb:98-111` (`update_values`), chamado do
`before_validation` de **todo** save:

```
prev_bal = original_balance                       # já negativo (BE-263)
movements.order(date: :asc, created_at: :asc).each_with_index do |mov, i|
  mov.balance  = prev_bal + (sinal(mov.movement_type) * mov.movement_value)
  mov.sequence = i + 1                            # reatribuído a partir de 1
  prev_bal     = mov.balance
end
persist(movs)                                     # pulando validações
operation.balance = prev_bal                      # ou original_balance se não houver movimento
```

`sinal` vem de `../sfg/app/models/risk_movement_type.rb:53-61`: crédito `"C"` → **−1**,
débito `"D"` → **+1**.

### Forma no ai9

```ruby
# backend/app/services/risk/calculator.rb  (o mesmo arquivo de S5)
module Risk
  class Calculator
    class << self
      # ... fórmulas de exposição entregues em S5 ...

      def recalculate_chain(operation)   # BE-265 — DEC-01 + DEC-02
      def last_movement(operation)       # BE-255 — por `sequence` asc, não por data
    end
  end
end
```

### Quem chama

| Chamador | Caminho |
| -------- | ------- |
| **Gravação da operação** | `before_validation` de `RiskOperation` → `recalculate_chain` |
| **Gravação do movimento** | `after_commit` de `RiskMovement` → salva a operação → `recalculate_chain` |
| **Exclusão do movimento** | `after_destroy` → salva a operação → `recalculate_chain` + renumeração |
| **Prorrogação** | `after_create` de `RiskOperationExtension` sobrescreve `due_date` → `recalculate_chain` |
| **Leitura do extrato** | `MovementsTab` lê `risk_movements.balance`, que **é** a saída do serviço |
| **Cartão "última movimentação"** | `Risk::Calculator.last_movement` — o mesmo serviço |

**A regra que não pode ser quebrada:** nenhum componente React soma saldo. O sufixo `C`/`D`
e a cor da célula são formatação; o número vem pronto.

### Três detalhes que parecem otimizáveis e não são

| Detalhe | Por que é comportamento, não acaso |
| ------- | ---------------------------------- |
| Ordenação `date asc, created_at asc` | Reordenar por `id` **muda saldo** quando dois movimentos têm a mesma data. O índice de `DB-236` existe exatamente para essa ordenação |
| `sequence` reatribuído a partir de 1 em cada recálculo | É o que a coluna "sequência" do extrato mostra e o que `last_movement` usa para achar o último |
| A persistência **pula validações** | Consequência preservada: a janela de datas de `BE-274` **não** é reaplicada nesse caminho. Reaplicá-la faria recálculos legítimos falharem em dado histórico |

`activerecord-import` (usado no legado) **não está no `backend/Gemfile`** — verificado. O
equivalente é `upsert_all` do Rails 8, que também pula validações (`OPS-235`, correção
**C-03** do mapa).

## 2. Golden tests — os valores e de onde saem

Derivados da leitura direta da fonte legada (o legado não tem suíte, D-114). Cada tarefa de
golden inclui **reconferir contra o dump** quando ele estiver disponível.

**Cenário `M1` — a cadeia.** Tipo **sem** pré-faturamento; capital 100.000,00; saldo inicial
informado 100.000,00 (gravado **−100.000,00**, `risk_operation.rb:34`); emissão 01/03/2026;
vencimento 30/06/2026.

| # | Data | Tipo de movimento | credit_type | sinal | Valor | `balance` | `sequence` |
| - | ---- | ----------------- | ----------- | ----- | ----- | --------- | ---------- |
| 1 | 01/03/2026 | Liberação do Recurso | D | +1 | 100.000,00 | **0,00** | 1 |
| 2 | 15/03/2026 | Juros | D | +1 | 2.500,00 | **2.500,00** | 2 |
| 3 | 20/04/2026 | Liquidação | C | −1 | 30.000,00 | **−27.500,00** | 3 |

`risk_operations.balance` = **−27.500,00** (o último saldo).

Casos derivados que o mesmo golden trava:
- Inserir um movimento **no meio** (10/03, Juros, 1.000,00) renumera tudo e produz
  0,00 → 1.000,00 → 3.500,00 → −26.500,00.
- Excluir o movimento automático de "Liberação do Recurso" **é permitido** e ele **não é
  recriado** — a cadeia passa a 2.500,00... a partir de −100.000,00: −97.500,00 e
  −127.500,00. Replicar.
- Operação **sem nenhum movimento**: `balance = original_balance` (−100.000,00), mas
  `balance_on(qualquer data)` devolve **0,00** (S5, `BE-266`). Os dois convivem — é assim
  que o legado calcula.
- Movimento com valor que **zera** o saldo, saldo negativo e movimento em operação
  encerrada **continuam permitidos**.

**Cenário `M2` — transferência pré↔antecipação.** Limite de tipo com pré-faturamento; o par
estático de S5 (`BE-241`), ambos com saldo 0,00.

| Operação | Movimento | credit_type | sinal | Valor | Saldo |
| -------- | --------- | ----------- | ----- | ----- | ----- |
| pré (`is_pre`) | Valor Transferido | C | −1 | 10.000,00 | **−10.000,00** |
| antecipação (par) | Transferência Recebida | D | +1 | 10.000,00 | **+10.000,00** |

Mesma data, mesmo valor, mesma observação, `pair_id` cruzado. Sem o par, a operação é
recusada **antes** de gravar o movimento original (hoje fica meia transferência).
Transferir **a partir da antecipação não gera contrapartida** — replicar (**Q-R11**).

**Cenário `M3` — renovação (D-94, IMP-R1).** Original: emissão 01/03/2026, vencimento
30/06/2026. Renovada em 20/05/2026.

| Grandeza | Valor esperado | Regra |
| -------- | -------------- | ----- |
| Prazo decorrido | **80 dias** | `hoje − issue_date_original` |
| Novo vencimento | **18/09/2026** | `due_date_original + 80 dias` — preserva o prazo |
| `original_id` da nova | **id da raiz** da cadeia, não o da clicada | `original.original_id || original.id` |
| `original_due_date` da nova | **30/06/2026** | vencimento da que foi renovada |
| `is_ended` da nova | **falso** | forçado |
| `is_ended` da **original** | **verdadeiro** | **D-94 — muda em relação ao legado (IMP-R1)** |
| Exposição em 01/06/2026 | conta **uma** operação, não duas | consequência do anterior |

Campos copiados: título, tipo, projeto, empresa, portador, contrato, `operation_value`,
`agreed_rate`, observação, `is_on_variable`, `receivable_id`, `operation_subtype_id`,
`original_balance` (verificado em `../sfg/app/models/risk_operation.rb:113-139`).

**Cenário `M4` — prorrogação.** Operação com vencimento 30/06/2026 e um movimento em
20/04/2026.

| Passo | Resultado esperado |
| ----- | ------------------ |
| Prorrogar para 31/08/2026 | `original_due_date` carimbado **da operação** (o valor do form é ignorado); `operation.due_date` vira 31/08/2026; a cadeia é recalculada |
| Prorrogar para 15/06/2026 (**encurtar**) | **422** — `new_due_date > original_due_date` passa a valer no servidor. Hoje só o `minDate` do datepicker impede |
| O log | é **imutável**: não há update exposto |

**Cenário `M5` — última movimentação (`BE-255`).**

| Situação | Resultado esperado |
| -------- | ------------------ |
| Operação de `M1` | o movimento de **maior `sequence`** (Liquidação), `movement_value_sign = −1`, `total_balance = −27.500,00`, `original_balance = −100.000,00` |
| Operação **sem** movimento (estática recém-criada) | **payload vazio**. Hoje o legado faz `.date` em `nil` → **500 na abertura do detalhe** |

## 3. Escopo por projeto (C1) — onde estão as IDORs

```ruby
project = current_project!
scope   = RiskOperation.for_project(project)
scope   = scope.where(id: params[:risk_operation_id]) if params[:risk_operation_id]
# NUNCA: RiskOperation.where(id: params[:risk_operation_id])  ← o que o legado faz
```

| Endpoint | O que o legado faz | O que o ai9 faz |
| -------- | ------------------ | --------------- |
| `risk_operations#search` (`BE-253`) | `risk_operation_id` **substitui a relation inteira**, perdendo o escopo — vaza operação de qualquer projeto | filtra **dentro** do escopo |
| `risk_movements#search` (`BE-270`) | **nenhum** escopo de projeto: qualquer `risk_operation_id` é aceito | escopo herdado da operação, validado |

Todos os movimentos carimbam `company_id`/`carrier_id`/`project_id` **da operação**,
descartando o que vier no payload (`BE-272`) — replicar: é o que mantém o dado histórico.

## 4. Grupos de IDs → camada alvo em ai9

### Dados — `DB-235` (mapa §2.3)
Só uma migration nesta fatia: `risk_operations`. As outras 6 tabelas de risco nascem em
**S5**. Índices em (`project_id`, `issue_date`, `due_date`), `risk_control_id`,
`operation_subtype_id`, `original_id`, `receivable_id`, `receipt_id`; FKs reais;
`is_ended`/`is_on_variable` → boolean; sentinelas → `is_static`; **`original_balance` migra
com o sinal negativo preservado** (DEC-01). `balance` continua **coluna cache derivada** —
não coluna gerada: o legado a lê direto na lista e ela é reescrita pelo recálculo.

### Backend — `BE-253…BE-277`, `OPS-235`, `OPS-237`
- `backend/app/models/{risk_operation,risk_movement,risk_operation_extension}.rb`
- `backend/app/services/risk/{operation_service,movement_service,transfer_service,renewal_service,extension_service}.rb`
  + os dois métodos novos em `calculator.rb` — padrão `class << self` + `ApiResponseHandler`
- `backend/app/controllers/api/v1/risk_operations.rb` (com movimentos, extensões e renovação
  aninhados) + `api/entities/risk_operation.rb`, `risk_movement.rb`,
  `risk_operation_extension.rb`
- A cascata de criação (`BE-256`) é **uma transação**:
  `BE-261` resolve o limite pela quádrupla → `BE-262` concilia tipo↔subtipo →
  `BE-263` força o sinal → `BE-264` cria o movimento de liberação →
  `BE-265` recalcula. Qualquer falha desfaz tudo; hoje falhas intermediárias deixam a
  operação gravada sem par, sem movimento ou sem limite, em silêncio.

### Frontend — `FE-250…FE-276`
`frontend/src/features/risk/{pages,components,api,types}/`, React Query v5, zero
`setInterval`. Consome `DataTable`, `Pagination`, `MoneyInput`, `EmptyState`/`ErrorState` e
`DateRangePicker` — todos membros da **biblioteca compartilhada**, entregues por S0/S5.

Duas telas concentram o risco visual:
- **Detalhe da operação** (`FE-264`): três abas com deep-link real (D-92), a aba
  PRORROGAÇÕES só para tipo sem pré-faturamento.
- **Extrato** (`FE-269`/`FE-270`): o sufixo `C`/`D` colado no valor (`R$ 1.234,56C`) é
  **replicado** — é como o operador lê o extrato hoje. A cor vem do par único de tokens
  semânticos criado em S5 (D-101), não das duas paletas concorrentes do legado.

### Contratos entre blocos — `DB-239`, `OPS-238`
Escritos aqui, **implementados no bloco `receivables` (S6)**:
- subtipo de tipo **com** pré → localiza a operação estática de (projeto, empresa,
  portador, tipo, subtipo) e cria `RiskMovement` de "Liberação do Recurso" com
  `movement_value = valor_liquido`;
- subtipo de tipo **sem** pré → cria (ou revincula) `RiskOperation` "Operação do recebível
  #id" com `operation_value = valor_liquido`, `due_date = data_credito`,
  `agreed_rate = nominal_tax`, `contract_number = nro_bordero`;
- validação prévia rejeita o recebível com "Não possui limite cadastrado" se não houver
  `RiskControl` ativo;
- resolução do tipo de movimento por `integration_key` (B-09).

Esta fatia entrega o **teste de integração** desse contrato; o código de borderô é de S6.

## 5. Conflitos entre o mapa e a spec — como foram resolvidos

Dois `build?` desta fatia são divergências entre `.migration-ai9/map/risk-indicators.md` e
`openspec/specs/risk/spec.md`. **A spec vence** (é o requirement aprovado no Phase 1), e a
divergência vira tarefa de decisão. Registrado aqui para ninguém "corrigir" de volta:

| ID | Mapa diz | Spec diz | Adotado |
| -- | -------- | -------- | ------- |
| `BE-262` | replicar "o primeiro subtipo" | recusar, pedindo escolha explícita | **spec** (T-D3) |
| `BE-268` | bloquear movimento e prorrogação em operação encerrada | encerrada continua na janela, consumindo limite e aceitando movimentos | **spec** (T-D4) |

`FE-260` não é conflito: a spec de risco deixa a pergunta aberta e a spec irmã de
estruturadas (`FE-297`) já a resolve como regra de servidor. Adotada a mesma semântica nos
dois módulos (T-D5).

## 6. O que fica registrado, não corrigido (Princípio 6b)

| Achado | Ação |
| ------ | ---- |
| `aasm` no `Gemfile:45`, **declarada e não usada** | Não ativar. `is_ended` vira `enum` string + service, que é o padrão vivo da base (`ai9-conventions.md` §9.6). Linha em `upstream-flags.md` |
| `pg_search` no `Gemfile:87` sem uso na base | A busca de operações usa `ILIKE` nativo. `pg_search` fica como opção, não padrão |
| Os 13 textos de ajuda do formulário são **todos o mesmo placeholder** no legado | Portar o mecanismo (carregado uma vez, não `YAML.load_file` por render). Conteúdo em branco até o negócio escrever (**Q-R9**) |

## 7. Ordem de execução e critério de pronto

Ordem: **dados → backend → frontend → testes → paridade**, com a mesma trava de S5: **o
golden nasce junto com a regra**. `M1` (cadeia) e `M2` (transferência) precisam estar verdes
antes de qualquer tela de extrato existir, e `M3` antes de a renovação ser exposta — porque
`M3` **muda número de propósito** e sem golden ninguém consegue provar que mudou só o que
deveria.

Uma tarefa está pronta quando o comportamento existe ponta a ponta, o teste que a cobre
passa (golden inclusive), o gate de autorização foi verificado **nos dois lados** (C3) e o
`parity-ledger.md` recebeu o ID.
