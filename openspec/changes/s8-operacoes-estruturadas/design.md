# Design: S8 — Operações estruturadas e remuneração em ai9

> As 98 linhas item-a-item **não são duplicadas aqui**. A fonte é
> `.migration-ai9/map/risk-indicators.md` **§2.4** (`structured-operations` — operações,
> tipos, remunerações e recursos). Cada linha lá traz "Equivalente ai9", "O que muda",
> "Melhoria proposta" e "Risco". Este documento descreve **o desenho**.

## 1. `Structured::RemunerationCalculator` — a única fórmula de faturamento (C2)

### A sequência exata, medida na fonte

`../sfg/app/models/receipt.rb:41-66` (`Receipt#fetch`), na ordem em que acontece:

1. `receipt_id` já preenchido na operação → erro de negócio "Já existe um recibo associado
   a essa operação";
2. copia `project_id`, `operation_title` e `date = operation.issue_date`;
3. busca a remuneração por (`project_id`, `operation_type_id`, `operation_type_type`) — a
   unicidade de `BE-301` garante **uma só**;
4. sem remuneração → erro de negócio "Não existe remuneração no projeto para esse tipo de
   operação";
5. **congela** no recibo: `kind = remuneration.beauty_type`, `title = remuneration.title`,
   `fee = remuneration.value`, `operation_value = operation.operation_value`;
6. **`value = operation_value * (fee.to_f / 100.0)`**;
7. `temp_id = "RCP-#{project_id}-#{kind}-#{remuneration_id}-#{operation_id}"`.

**Sem arredondamento explícito, sem pro-rata, sem prazo**: nem `agreed_rate`, nem
`issue_date`/`due_date`, nem `balance` entram. O passo 6 é `decimal(15,2) × Float`, e o
arredondamento que chega ao banco vem do **cast na gravação** — é acidental, e é o que
**DEC-02** manda replicar.

### Forma no ai9

```ruby
# backend/app/services/structured/remuneration_calculator.rb
module Structured
  class RemunerationCalculator
    class << self
      include ApiResponseHandler

      # Calcula o recibo de UMA operação. Não persiste.
      # operation: RiskOperation (LIQ) ou StructuredOperation (EST)
      # => { kind:, title:, fee:, operation_value:, value:, date:, operation_title:, temp_id: }
      def calculate(operation)            # BE-305

      # Candidatos a cobrança de um projeto, já calculados.
      def candidates(project)             # BE-306
    end
  end
end
```

### Quem chama

| Chamador | Caminho | Observação |
| -------- | ------- | ---------- |
| **Prévia da tela de cobrança** | `GET .../charges/:id/receipt_candidates` → `candidates` | Cada candidato já vem **com o valor calculado** — é o comportamento do legado, onde `Receipt.new(operation:)` dispara o setter |
| **Gravação do recibo** | `Receipt#fetch` (bloco `charges`) → `calculate` | **O mesmo serviço.** Não existe uma segunda implementação |
| **`Charge#calc!`** | soma os `receipts.value` já gravados | Bloco vizinho; consome, não recalcula |

**A regra que não pode ser quebrada:** nenhum componente React multiplica capital por taxa.
O `%` na célula é rótulo; o valor vem pronto.

### Por que a política de arredondamento passa a ser explícita

Hoje ela é implícita (o cast). No ai9 ela é **escrita e documentada** — `ROUND_HALF_UP`, 2
casas no valor final — **reproduzindo** o resultado atual, comprovado por golden. Isso é
diferente de mudá-la: `DB-296` padroniza o **armazenamento** (`decimal(14,2)` para valores,
`decimal(7,4)` para taxas) sem tocar na **sequência de cálculo**. Replicar o resultado não
obriga a replicar o tipo de armazenamento.

## 2. Golden tests — os valores e de onde saem

Derivados da leitura direta da fonte e conferidos executando a mesma aritmética Ruby
(`BigDecimal × Float`) que o legado executa. Cada tarefa de golden inclui **reconferir
contra o dump**.

| # | `operation_value` | `fee` | Produto exato do cálculo | Gravado em `decimal(_,2)` | Por que este caso existe |
| - | ----------------- | ----- | ------------------------ | ------------------------- | ------------------------ |
| **E1** | 200.000,00 | 2,55 | 5100.0 | **5.100,00** | caso limpo, sem arredondamento |
| **E2** | 1.234,56 | 2,55 | 31.48128 | **31,48** | truncamento comum |
| **E3** | 87.654,32 | 1,75 | 1533.9506 | **1.533,95** | quarta casa arredonda para baixo |
| **E4** | 10.000,20 | 2,55 | 255.0051 | **255,01** | **fronteira**: terceira casa é 5 |
| **E5** | 99.999,99 | 7,77 | 7769.9992229999990000001 | **7.770,00** | **o artefato do float aparece na 10ª casa** — é a prova de que a aritmética é float, e o golden trava isso |

`temp_id` esperado: `RCP-{project_id}-EST-{remuneration_id}-{operation_id}` para operação
estruturada e `RCP-{project_id}-LIQ-…` para operação de risco.

Casos de erro que o mesmo golden trava:
- operação com `receipt_id` preenchido → erro de negócio, **409/422**, não exceção não
  tratada (hoje `ArgumentError` derruba a requisição com 500);
- projeto sem remuneração para o tipo → erro de negócio, mesma mudança;
- `operation_type_type` inválido → 422 na criação da remuneração, e `beauty_type` **nunca**
  chega a `"???"`.

**Cenário `E6` — o `balance` decorativo (`BE-292`, Q-R3).**

| Passo | Resultado esperado |
| ----- | ------------------ |
| Criar com saldo inicial informado 50.000,00 | `original_balance = −50.000,00` **e** `balance = −50.000,00` |
| Editar **apenas a observação** | `balance` volta a **−50.000,00** |
| Qualquer caminho do legado que dê baixa nesse saldo | **não existe** — varredura completa |

**Cenário `E7` — candidatos a cobrança (`BE-306`).** Para cada remuneração do projeto,
`operation_class.where(project_id:, operation_type_id:, receipt_id: nil)`. Operações
**encerradas continuam candidatas** (Q-R18) — replicar.

## 3. Escopo por projeto (C1) e a superfície sem autenticação

```ruby
project = current_project!
scope   = StructuredOperation.for_project(project)
scope   = scope.where(id: params[:structured_operation_id]) if params[:structured_operation_id]
```

| Endpoint | O que o legado faz | O que o ai9 faz |
| -------- | ------------------ | --------------- |
| `structured_operations#search` (`BE-280`) | `structured_operation_id` **descarta o escopo inteiro** — vazamento cross-project para qualquer autenticado | filtra dentro do escopo; o parâmetro continua existindo (o front usa para "detalhe embutido") |
| `structured_operations#update` (`BE-286`) | `fetch_structured_operation` busca por id **sem escopo** — dá para editar operação de outro projeto sabendo o id | busca dentro do escopo |
| `remunerations#create` (`BE-301`) | `project_id` vem de campo **hidden** e não é forçado — dá para criar remuneração em outro projeto | `project_id` forçado ao projeto corrente |
| `remunerations#update` (`BE-302`) | busca sem escopo | busca dentro do escopo |
| **todos os controllers dedicados da unidade** (`FE-309`) | herdam `requires_current_user? == false`: `search`/`create`/`update`/`destroy` **não exigem login pelo `before_action`** — funcionam só porque `current_user` precisa existir para `current_user.default_project_id` não quebrar | **todo endpoint exige JWT válido + policy** |

`structured_operation_types`, `resource_sources` e `resource_kinds` são **catálogo global**,
sem escopo de projeto (§0.6 regra 4). `structured_operations` e `remunerations` são **por
projeto**.

## 4. Grupos de IDs → camada alvo em ai9

### Dados — `DB-280…DB-297` (mapa §2.4)
`backend/db/migrate/*.rb` + `schema.rb`, convenção `ai9-conventions.md` §4.

Cinco decisões de esquema que mudam comportamento se erradas:
- **`DB-282`** — nenhuma das 5 migrations legadas declara `foreign_key: true`, e a única
  `add_index` é a implícita de `t.references` em `remunerations`. Com FKs reais somem dois
  estados impossíveis de ler: remuneração apagada deixando recibo órfão (`BE-303`) e
  operação com carrier apagado sumindo da lista pelo INNER JOIN (`BE-280`).
- **`DB-284`** — o índice **único composto** (`project_id`, `operation_type_type`,
  `operation_type_id`) é o que garante que `Receipt#fetch` ache **uma** taxa. Hoje a
  unicidade só existe em `validates_uniqueness_of`, sujeita a corrida.
- **`DB-281`** — a relação circular `structured_operations.receipt_id` ×
  `receipts.operation_id`/`operation_type`. Manter só o lado `receipts` é o desenho limpo,
  **mas o escopo `available_for_receipt` depende da coluna**. Decisão conjunta com o bloco
  `charges`; enquanto isso, a coluna fica, com índice obrigatório.
- **`DB-295`** — 9 flags integer viram boolean com mapeamento **`≠ 0 → true`**. Valores
  `2+` existentes no banco viram `true`; o dry-run do ETL **lista as ocorrências antes**.
- **`DB-296`** — padronização de precisão **sem** mudar a sequência de cálculo. É o item
  mais perigoso da fatia: `Charge#calc!` soma esses valores.

`DB-285` mantém `remunerations.title` **desnormalizado** (decisão **B-06**): trocar por join
muda o resultado da busca para registros criados antes da migration que adicionou a coluna,
que têm `title` NULL até o primeiro save. Ganho estético, custo de paridade.

### Backend — `BE-280…BE-308`, `BE-720…BE-729`
- `backend/app/models/{structured_operation,structured_operation_type,remuneration,resource_source,resource_kind}.rb`
- `backend/app/services/structured/{operation_service,operation_type_service,remuneration_service,remuneration_calculator,resource_source_service,resource_kind_service}.rb`
  — padrão `class << self` + `ApiResponseHandler`
- `backend/app/controllers/api/v1/{structured_operations,structured_operation_types,remunerations,resource_sources,resource_kinds}.rb` + entities

Três correções que mudam status HTTP e por isso mudam o que a tela faz:
- `BE-287`/`BE-724`/`BE-729` — o ternário degenerado `errors.any? ? :ok : :ok` faz a
  exclusão bloqueada responder **200**; o front trata como sucesso e recarrega a lista com o
  registro ainda lá. Passa a **422 com a dependência**.
- `BE-294` — `Receipt#fetch` levanta `ArgumentError` **não tratado** → 500 no fluxo de
  cobrança. Passa a 409/422 com mensagem.
- `BE-303` — `has_many :receipts` sem `dependent:` vira `restrict_with_error`.

### Frontend — `FE-280…FE-309`
`frontend/src/features/structured-operations/{pages,components,api,types}/`, React Query v5.
Consome os membros da biblioteca compartilhada entregues por S0/S5 (`DataTable`,
`Pagination`, `MoneyInput`, `PercentInput`, `EmptyState`, `ErrorState`, `DateRangePicker`).

Duas telas concentram o valor:
- **Formulário** (`FE-293`/`FE-295`): o legado **não tem botão "Salvar"** — qualquer
  `change` registra a ação numa barra inferior de ações pendentes, e se **qualquer**
  obrigatório fica vazio a ação é **removida da barra sem mensagem**. O usuário perde a
  possibilidade de salvar e não sabe por quê. No ai9 vira barra de ação explícita que **diz
  o que falta**.
- **Remunerações** (`FE-304`/`FE-305`): sai a gambiarra dos dois selects sobrepostos com
  troca de `name`/`disabled_operation_type_id`; entra **um** select controlado por estado. O
  campo de taxa **não tem limite de faixa hoje** e continua sem (Q-R16) — é a taxa que
  multiplica todo o faturamento, então a decisão é do negócio, não da migração.

### Operação — `OPS-280…OPS-289`
Seeds idempotentes (`DB-292`, `DB-293`, `DB-294`), menu (`OPS-286`), allowlists
(`OPS-288`), formatação no front (`OPS-289`) e o spec do calculador (`OPS-287`).

`OPS-285`: o código do ETL Django é **descartado** (D-105), mas as colunas `legacy_*` são
**preservadas** — são a única prova de proveniência de `resource_sources`. `ResourceKind`
**não** participou daquela migração, o que reforça a Q-R5.

## 5. O portão de decisão de `resource_kinds` (Q-R5)

Sete IDs de superfície (`BE-307`, `BE-720`…`BE-724`, `FE-307`) ficam **atrás de um portão**,
e dois IDs de dados (`DB-286`, `DB-294`) **não** ficam. O critério é assimétrico de
propósito:

- **dado é irreversível** — se a tabela tiver linhas em produção e não for criada, elas se
  perdem. Custo de criar: uma migration e um seed de 5 linhas;
- **superfície é reversível** — se a decisão vier "portar", os 7 IDs são construídos com o
  desenho já escrito no mapa. Custo de esperar: zero.

O portão abre com um número: `SELECT COUNT(*) FROM receivable_entries WHERE resource_kind_id
IS NOT NULL`. **Zero → os 7 IDs e o `DB-289` viram `dropped` com evidência**, e a remoção da
tabela é uma tarefa explícita, nunca uma omissão.

## 6. O que fica registrado, não corrigido (Princípio 6b)

| Achado | Ação |
| ------ | ---- |
| `pg_search` no `Gemfile:87` sem uso na base | A busca usa `ILIKE` nativo; `pg_search` fica como opção |
| `paper_trail` no Gemfile **sem uso**; a auditoria da base é ad hoc | `created_by_id`/`updated_by_id` com FK real, sem ativar a gem (`DB-297`) |
| Os 13 textos de ajuda são **todos o mesmo placeholder** no legado | Portar o mecanismo, conteúdo em branco (**Q-R9**) |
| `resource_kinds` e `resource_sources` têm o **mesmo** rótulo de menu e título de aba | Se as duas sobreviverem, precisam de nomes distintos (**Q-R22**) |

## 7. Ordem de execução e critério de pronto

Ordem: **dados → backend → frontend → testes → paridade**, com a trava de sempre: **o
golden nasce junto com a fórmula**. `E1`…`E5` precisam estar verdes antes de qualquer tela
exibir prévia de recibo, e antes de `DB-296` mexer na precisão das colunas.

**E2 não fecha sem o handshake com `charges`/`receipts`**: a fórmula é desta fatia, a tabela
e o `Charge#calc!` são do bloco vizinho. Sem os dois lados, o faturamento não tem ponta a
ponta verificável.

Uma tarefa está pronta quando o comportamento existe ponta a ponta, o teste que a cobre
passa (golden inclusive), o gate de autorização foi verificado **nos dois lados** (C3) e o
`parity-ledger.md` recebeu o ID.
