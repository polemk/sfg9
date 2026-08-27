# Design: S5 — Limites de risco e motor de exposição em ai9

> As 66 linhas item-a-item **não são duplicadas aqui**. A fonte é
> `.migration-ai9/map/risk-indicators.md`, seções **§2.1** (catálogos e limites, 41 IDs),
> **§2.2** (motor de exposição, 12 IDs) e **§2.3** (console, posições diárias e
> transversais). Cada linha lá traz "Equivalente ai9", "O que muda", "Melhoria proposta" e
> "Risco". Este documento descreve **o desenho**, não o inventário.

## 1. `Risk::Calculator` — o coração da fatia (C2)

### O problema que ele resolve

No legado as fórmulas de exposição vivem espalhadas em **três models** que são cópias
literais umas das outras: `../sfg/app/models/risk_control.rb:115-160`,
`../sfg/app/models/company.rb:35-66,79-82,155-161,182-184` e
`../sfg/app/models/project.rb:462-493` — e `company.rb` ≡ `project.rb` linha a linha. Nada
disso tem teste (**D-114**). Qualquer divergência entre a leitura da tela e a apuração
usada na gravação é invisível.

### Forma no ai9

```ruby
# backend/app/services/risk/calculator.rb
module Risk
  class Calculator
    class << self
      include ApiResponseHandler

      # --- por limite (RiskControl) --------------------------------
      def operations_on(control, date)          # BE-242
      def balance_on(operation, date)           # BE-266
      def limite_utilizado_on(control, date)    # BE-243  DEC-01
      def limite_liquidavel_on(control, date)   # BE-244  DEC-01
      def limite_pre_on(control, date)          # BE-245  DEC-01
      def limite_disponivel_on(control, date)   # BE-246  DEC-01 + DEC-02
      def vencidos_on(control, date)            # BE-247  sem endpoint (B-12)
      def a_vencer_on(control, date)            # BE-248  sem endpoint (B-12)
    end
  end
end

# backend/app/services/risk/aggregate_service.rb
module Risk
  class AggregateService
    class << self
      def limite_total_on(scope, type, date)       # BE-249
      def perc_limite_utilizado_on(scope, date)    # BE-249  sprintf('%.2f')
      def controls_info_on(scope, date)            # BE-250  D-95 replicado
      def total_limits_on(company, date)           # BE-251  as 4 chaves iguais
      def summary_on(project:, company: nil, carrier: nil, date:)  # BE-231
    end
  end
end
```

`scope` é `Company` **ou** `Project`: o legado tem as duas cópias literais; no ai9 é **um**
service parametrizado pelo escopo. Mesma saída, metade do código.

### Quem chama

| Chamador | Caminho | Observação |
| -------- | ------- | ---------- |
| **Prévia da tela** (console de risco) | `GET /api/v1/risk_controls/summary` → `Risk::AggregateService.summary_on` | É o **mesmo** service. Não existe uma segunda implementação no front |
| **Prévia do resumo por empresa** | `GET /api/v1/companies/:id/total_limits` → `Risk::AggregateService.total_limits_on` | Endpoint exposto pelo bloco `companies-carriers`, cálculo daqui (BE-251) |
| **Gravação** — `after_create` do limite | `Risk::StaticPairService` lê `original_balance`/`original_balance_pre` do limite e abre o par | BE-241 |
| **Gravação** — recálculo da cadeia (S7) | `Risk::Calculator#recalculate_chain` (BE-265, construído em **S7**) reusa `balance_on` | O contrato é firmado aqui |
| **Validação de recebível** (S6) | `Risk::ControlService#available_for_entry_on` (BE-252) | Contrato OPS-238 |

**A regra que não pode ser quebrada:** nenhum componente React recalcula exposição. O front
formata o que o serviço devolveu (`Intl.NumberFormat('pt-BR')`, OPS-289). Se uma tela
precisa de um número que o serviço não devolve, o serviço ganha o número — não o front.

### Por que isto torna DEC-01 e DEC-02 auditáveis

`DEC-01` e `DEC-02` são melhorias **DECLINADAS pelo usuário** (`improvements-log.md`,
D-93 e D-104). Isso significa que o comportamento estranho é **o requisito**, e o único
jeito de provar que ele foi preservado é um teste que trava o número atual. Cada fórmula
tem um golden com valores derivados da leitura da fonte legada (§4 abaixo). Se alguém
"consertar" o sinal ou trocar o `.to_f` por `BigDecimal`, o golden quebra e diz exatamente
qual centavo mudou.

**QA não deve abrir bug** para: utilização negativa em saldo devedor, saldo inicial exibido
positivo no formulário e negativo no detalhe, coluna "Liquidável" mostrando o utilizado, e
percentual de cabeçalho exibindo valor monetário com "%" (D-95). Tudo isso é intencional.

## 2. A forma correta do `RiskControl` (C-09) — o que vai para a migration

Verificado na fonte, não deduzido:

| Migration legada | O que faz |
| ---------------- | --------- |
| `20210510211438_create_risk_controls.rb` | 8 colunas fixas: `limite_*`/`taxa_*` para auto_liquidaveis, fomento, comissaria, intercompany |
| `20220611152145_change_risk_control_fields.rb` | acrescenta `risk_operation_type_id`, `user_id`, `limite decimal(15,2)`, `taxa float`, `original_balance decimal(15,2)`, `original_balance_pre decimal(15,2)` |

**Modelo alvo no ai9:**

```
risk_controls
  project_id  FK  (derivado de company.project_id no before_validation — BE-239)
  company_id  FK
  carrier_id  FK
  risk_operation_type_id  FK
  title                 (cópia do título do portador, reescrita em todo save)
  limite                decimal(14,2)   -- UM limite
  taxa                  decimal(7,4)    -- UMA taxa
  original_balance      decimal(14,2)
  original_balance_pre  decimal(14,2)
  is_active             boolean NOT NULL  (int ≠ 0 → true)
  has_safegold_management boolean         (herdado da empresa)
  user_id               FK
  UNIQUE (company_id, carrier_id, risk_operation_type_id)     -- hoje só na aplicação
  INDEX  (project_id, is_active)
```

As 4 modalidades **não são colunas**: são linhas de `risk_operation_types`, cadastro aberto
(OPS-230 semeia Fomento, Comissária, Intercompany e Auto Liquidável com
`integration_key` estável). `has_pre_faturamento` no tipo é o que gera **1 ou 2 subtipos**
(`is_pre` 0/1, ligados por `pair_id`) e o que dispara o par estático de BE-241.

As 8 colunas pré-2022 **permanecem na migration inicial** até a contagem no dump (DB-240).
Preservar coluna vazia é barato; descartar coluna com dado é irreversível.

## 3. Grupos de IDs → camada alvo em ai9

### Dados — mapa §2.1 (DB-230…DB-240) e §2.3 (DB-231)
`backend/db/migrate/*.rb` + `schema.rb`. Convenção `ai9-conventions.md` §4: migration
`ActiveRecord::Migration[8.0]`, **nome de classe em pt-BR** com cabeçalho explicativo,
colunas em inglês, índices explícitos com `unique:`/`name:`, `comment:` nas colunas de
semântica não óbvia, dinheiro em `decimal(14,2)` e taxa em `decimal(7,4)`, flags `int → boolean`
com mapeamento **`≠ 0 → true`** (DB-295).

Duas escolhas de esquema que mudam comportamento se erradas:
- **`order` é palavra reservada em SQL** → a coluna de `risk_movements` vira `sequence`
  (DB-236). O payload da API expõe `sequence`.
- O índice de `risk_movements` é **(risk_operation_id, date, created_at)** — exatamente a
  ordenação do recálculo. Um índice por `id` faria o recálculo degradar **e** convidaria
  alguém a reordenar por `id`, o que **muda saldo**.

### Backend — mapa §2.1 (BE-230…BE-252, BE-278, BE-279) e §2.2 (BE-231…BE-266)
- `backend/app/models/risk_control.rb`, `risk_operation_type.rb`,
  `risk_operation_subtype.rb`, `risk_movement_type.rb`, `risk_entry.rb`
- `backend/app/services/risk/{control_service,operation_type_service,movement_type_service,static_pair_service,calculator,aggregate_service,entry_service}.rb`
  — padrão `class << self` + `include ApiResponseHandler` (`ai9-conventions.md` §3.6)
- `backend/app/controllers/api/v1/{risk_controls,risk_operation_types,risk_movement_types}.rb`
  — Grape, `desc`/`params`, `process_service_response`, `set_pagination_headers`
- `backend/app/controllers/api/entities/risk_*.rb`

### Frontend — mapa §2.1 (FE-240…FE-249, FE-277, FE-278) e §2.3 (FE-230…FE-239)
- `frontend/src/features/risk/{pages,components,api,types}/` — layout de feature folder
  copiado de `features/chat-builder/`
- Dados por **React Query v5** (`lib/api/client.ts` + `endpoints.ts`); zero `setInterval`
- Membros **novos da biblioteca compartilhada** (`components/ui/`), nunca peça de uma tela
  só (Princípio 11): `Pagination`, `MoneyInput`, `PercentInput`, `EmptyState`, `ErrorState`,
  `DateRangePicker` e `lib/format/money.ts`

> `Pagination`, `MoneyInput`/`PercentInput`, `EmptyState`/`ErrorState` e `DataTable` são
> declarados pela fatia **S0** (`projects-cadastros.md` §S0). Se já existirem quando esta
> fatia começar, **consumir**. Se não existirem, esta fatia os cria **na biblioteca**, não
> dentro de `features/risk/`. O `DateRangePicker` é o único que **não** está no S0: nasce
> aqui, compartilhado, porque seis telas do bloco dependem dele.

### Operação — mapa §2.1 (OPS-230…OPS-236) e §2.3 (OPS-239)
Seeds idempotentes por `integration_key` em `backend/db/seeds/`. As chaves
`fomento`/`comissaria`/`intercompany`/`auto_liquidavel` e as dos 3 tipos funcionais de
movimento (`liberacao_do_recurso`, `valor_transferido`, `transferencia_recebida`) são
**contrato** — B-09 troca a resolução por título literal por resolução por chave, com guarda
que falha **antes** de gravar.

## 4. Golden tests — os valores e de onde saem

Derivados da leitura direta da fonte legada (o legado não tem suíte para extrair, D-114).
Cada valor abaixo é reproduzível a partir das linhas citadas; a tarefa de golden inclui
**reconferir contra o dump** quando ele estiver disponível.

**Cenário `L1`** — tipo **sem** pré-faturamento, limite 200.000,00, taxa 2,55;
uma operação com capital 100.000,00, saldo inicial informado 100.000,00
(gravado como −100.000,00 — `risk_operation.rb:34`), emissão 01/03/2026, vencimento
30/06/2026, movimentos:

| Data | Tipo | credit_type | sinal | Valor | Saldo resultante |
| ---- | ---- | ----------- | ----- | ----- | ---------------- |
| 01/03 | Liberação do Recurso | D | +1 | 100.000,00 | **0,00** |
| 15/03 | Juros | D | +1 | 2.500,00 | **2.500,00** |
| 20/04 | Liquidação | C | −1 | 30.000,00 | **−27.500,00** |

| Fórmula | Data | Valor esperado | Fonte legada |
| ------- | ---- | -------------- | ------------ |
| `balance_on` | 28/02/2026 | **0,00** (não −100.000,00) | `risk_operation.rb:92-96` |
| `balance_on` | 31/03/2026 | **2.500,00** | idem |
| `balance_on` | 01/05/2026 | **−27.500,00** | idem |
| `limite_utilizado_on` | 31/03/2026 | **−2.500,00** | `risk_control.rb:115-124` (`× −1`) |
| `limite_utilizado_on` | 01/05/2026 | **27.500,00** | idem |
| `limite_disponivel_on` | 31/03/2026 | **202500.0** (Float) | `risk_control.rb:158-160` (`.to_f`) |
| `limite_disponivel_on` | 01/05/2026 | **172500.0** (Float) | idem |
| `perc_limite_utilizado_on` | 01/05/2026 | **"13.75%"** | `company.rb:51` (`sprintf('%.2f')`) |

**Cenário `L2`** — tipo **com** pré-faturamento, limite criado com saldo inicial liquidável
50.000,00 e pré 30.000,00. O `after_create` abre duas operações estáticas
(`operation_value: 0`, `balance: 0`, sem movimento):

| Fórmula | Valor esperado | Por quê |
| ------- | -------------- | ------- |
| `balance_on(estática, qualquer data)` | **0,00** | não há movimento; `balance_on` devolve **0**, não `original_balance` |
| `limite_utilizado_on` | **0,00** | consequência do anterior — o saldo inicial configurado **não** entra no agregado |
| `operations_on(qualquer data)` | inclui **sempre** as duas estáticas | `is_static` (B-08) substitui a sentinela de ±2000 anos |
| `available_for_entry_on` | **não** lista este limite | as estáticas estão sempre na janela (BE-252) |

> O primeiro item de `L2` é **a linha mais fácil de "consertar sem querer" do bloco
> inteiro**. É assim que o painel calcula hoje.

**Cenário `L3`** — agregado por tipo: dois limites ativos (200.000,00 e 300.000,00) e um
inativo (100.000,00) do mesmo tipo.

| Fórmula | Valor esperado |
| ------- | -------------- |
| `limite_total_on` | **500.000,00** (só ativos; ignora a data) |
| `perc_limite_utilizado_on` com `total = 0` e `utilizado > 0` | **"100.00%"** |
| `perc_limite_utilizado_on` com `total = 0` e `utilizado ≤ 0` | **"0.00%"** |
| `controls_info_on` → `formatted_limite_liquidavel` | recebe o **utilizado** formatado como moeda (D-95, **replicado**) |
| `controls_info_on` → `perc_liq`/`perc_pre` do agregado por tipo | recebem **valor monetário** e a view acrescenta "%" (D-95, **replicado**) |
| `total_limits_on` → `liq`, `perc_liq`, `pre`, `perc_pre` | as **4 chaves** devolvem a mesma string de `perc_limite_utilizado_on` (`company.rb:79-82`, **replicado**) |

**Cenário `L4`** — decisão **B-02**, as duas verdades da desativação: o mesmo limite
desativado, com uma operação vigente.

| Leitura | Resultado esperado |
| ------- | ------------------ |
| `RiskControl#operations` (tela de Operações de Risco) | a operação **continua listada** |
| `Company#operations_on` → resumo do console | a operação **some** |

Dois goldens separados. Unificar muda exposição financeira.

## 5. Escopo por projeto (C1) — como cai em cada endpoint

Forma canônica adotada de `projects-cadastros.md` §0.6, sem variação:

```ruby
project = current_project!                          # 403/404 iguais se não houver membership
scope   = RiskControl.for_project(project)
scope   = scope.where(id: params[:risk_control_id]) if params[:risk_control_id]
# project_id vindo do corpo da requisição é SEMPRE ignorado
```

| Recurso | Escopo |
| ------- | ------ |
| `risk_controls`, `risk_entries` | **por projeto** |
| `risk_operation_types`, `risk_operation_subtypes`, `risk_movement_types` | **catálogo global** — sem escopo. Leitura liberada ao Colaborador (DEC-18.4), escrita por papel |

Nada nesta fatia usa `default_scope`. O valor de `current_project_id` é **revalidado a cada
request**, e projeto inexistente e projeto sem membership respondem **o mesmo status**.

## 6. O que fica registrado, não corrigido (Princípio 6b)

| Achado | Onde | Ação |
| ------ | ---- | ---- |
| **UF-1** | `frontend/src/components/RichTextInput.tsx` usa `dangerouslySetInnerHTML` sem sanitização e não há DOMPurify | Linha em `upstream-flags.md`. Esta fatia não consome rich text |
| **C-07** | Kaminari no `Gemfile:85` sem uma única chamada em `backend/app` | Linha em `upstream-flags.md`; a escolha do padrão é do S0 |
| **§4 do mapa** | `aasm` no `Gemfile:45` sem uso | Não ativar. O padrão vivo é `enum` string + service |
| **C-06** | `ai9-conventions.md` §4 é pré-trim (cita concerns e tabelas que não existem mais) | Já registrado no mapa §6.1; seguir a regra de estilo, não a lista de arquivos |

## 7. Ordem de execução e critério de pronto

Ordem: **dados → backend → frontend → testes → paridade**, com uma trava: **o golden de
cada fórmula é escrito junto com a fórmula, não depois**. Nenhuma tela consome o motor de
exposição antes de os goldens de `L1`, `L2` e `L3` estarem verdes.

Uma tarefa está pronta quando:
1. o comportamento existe ponta a ponta (dado → serviço → endpoint → tela, no que se aplica);
2. o teste que a cobre passa e, para as fórmulas, o **golden** passa;
3. o gate de autorização foi verificado **nos dois lados** (C3);
4. o `parity-ledger.md` recebeu o ID.
