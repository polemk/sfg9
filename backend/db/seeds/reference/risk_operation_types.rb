# frozen_string_literal: true

# Seed de REFERÊNCIA dos **tipos de limite de risco** (OPS-230 / DB-574).
# Idempotente por `integration_key`.
#
# Sem estas quatro linhas nenhum `RiskControl` pode ser criado — o tipo é
# obrigatório — e o console "Controle de Risco" sobe sem um único cabeçalho.
# As chaves `fomento`, `comissaria`, `intercompany` e `auto_liquidavel` são
# CONTRATO com o ETL (S14).
#
# **Ponto de entrada individual** — ver a nota em `user_types.rb`.
puts '📐 Tipos de limite de risco (OPS-230)…'
Seeds::Reference::Runner.call_one!('Seeds::Reference::RiskOperationTypes', io: $stdout)
