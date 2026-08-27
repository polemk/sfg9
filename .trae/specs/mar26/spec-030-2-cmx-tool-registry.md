# Tarefa 030.2: CMX Tool Registry (Entries + Balances)

**Sprint:** 2 — Agente Nathy Nativo
**Estimativa:** 1.5 dias
**Tipo:** Backend

---

## Contexto

O agente Nathy precisa de tools para responder perguntas financeiras
e registrar lançamentos. No n8n, isso era feito via HTTP para `dsl/v1/mcp`.
No `comandae`, as tools consultam o banco **diretamente** via ActiveRecord.

**Regra:** o agente trabalha com `entries` (fluxo de caixa pontual) e
`balances` (consolidados). Nunca consulta `sales` do PDV.

Pasta: `backend/app/services/ai/tools/cmx/`

---

## Onde começa

- `ToolRegistry` já existe com 3 tools (capture_lead, search/list assets)
- `ToolExecutor` faz dispatch por switch-case
- Models `Entry` e `Balance` existem com seus services

## Onde termina

- 10 novas tools CMX registradas e funcionais
- Agente consegue consultar saldos e CRUD de lançamentos

---

## Tools a implementar

### Grupo `entries` (read + write)

| Classe | Tool name | Desc |
|---|---|---|
| `Cmx::ListEntries` | `list_entries` | Lista lançamentos por período |
| `Cmx::CreateEntry` | `create_entry` | Cria lançamento manual |
| `Cmx::UpdateEntry` | `update_entry` | Edita lançamento manual |
| `Cmx::DeleteEntry` | `delete_entry` | Remove lançamento manual |

Parâmetros seguem o controller existente (`entries.rb`):
- `date_start`, `date_end` (YYYY-MM-DD) para listagem
- `title`, `entry_type` (income/expense), `balance_date`, `value`, `comment` para criação

### Grupo `balances` (read-only)

| Classe | Tool name | Desc |
|---|---|---|
| `Cmx::GetDailyBalance` | `get_daily_balance` | Saldo de um dia |
| `Cmx::GetMonthlyBalance` | `get_monthly_balance` | Saldo do mês |
| `Cmx::GetYearlyBalance` | `get_yearly_balance` | Resumo anual |
| `Cmx::GetPeriodBalance` | `get_period_balance` | Período customizado (até 6 meses) |
| `Cmx::GetExpensesByDescription` | `get_expenses_by_description` | Despesas agrupadas |

### Grupo `products` (read-only)

| Classe | Tool name |
|---|---|
| `Cmx::ListProducts` | `list_products` |

---

## Estrutura padrão de cada tool

```ruby
module Ai
  module Tools
    module Cmx
      class ListEntries
        DEFINITION = {
          name: "list_entries",
          description: "Lista lançamentos do fluxo de caixa em um período.",
          parameters: {
            type: "object",
            properties: {
              date_start: { type: "string", description: "Data inicial (YYYY-MM-DD)" },
              date_end:   { type: "string", description: "Data final (YYYY-MM-DD)" },
              entry_type: { type: "string", enum: %w[income expense] }
            },
            required: %w[date_start date_end]
          }
        }.freeze

        def self.execute(args, flow:, session:, **)
          restaurant = resolve_restaurant(session)
          return { success: false, message: "Restaurante não identificado." } unless restaurant

          entries = Entry.where(restaurant: restaurant, balance_date: args[:date_start]..args[:date_end])
          entries = entries.where(entry_type: args[:entry_type]) if args[:entry_type].present?

          summary = entries.map { |e| "#{e.balance_date}: #{e.title} R$#{e.value} (#{e.entry_type})" }
          { success: true, message: summary.any? ? summary.join("\n") : "Nenhum lançamento no período." }
        end
      end
    end
  end
end
```

### Resolução de restaurante

```ruby
# Busca restaurante pelo usuário associado ao telefone do lead
def self.resolve_restaurant(session)
  lead = session.lead
  user = User.find_by(phone: lead.phone)
  user&.restaurant || nil
end
```

---

## Integrar no ToolRegistry e ToolExecutor

1. Adicionar `CMX_TOOLS` array no `ToolRegistry` com as 10 DEFINITION
2. No `definitions_for`, incluir CMX_TOOLS quando `agent_config.tool_groups` incluir `"cmx"`
3. No `ToolExecutor`, adicionar cases ou dispatch dinâmico para `Ai::Tools::Cmx::*`

---

## Critérios de aceite

1. Console: `Ai::Tools::ToolExecutor.execute("list_entries", {date_start: "2026-03-01", date_end: "2026-03-31"}, flow: flow, session: session)` retorna lançamentos
2. `create_entry` cria `Entry` com `source_type: "manual"` e restaurante correto
3. `delete_entry` em entrada não-manual retorna erro
4. Agente, ao receber "qual meu saldo de hoje?", chama `get_daily_balance`
5. Nenhuma tool acessa dados fora do restaurante do usuário
6. Testes unitários para cada tool

---

## Dependências

- Spec 030.1 (áudio) para fluxo de entrada funcionando
- Models `Entry`, `Balance`, `Restaurant`, `User` existentes

## Próxima tarefa → Spec 030.3
