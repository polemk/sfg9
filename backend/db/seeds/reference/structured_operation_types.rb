# frozen_string_literal: true

# Seed de REFERÊNCIA dos **tipos de operação estruturada** (DB-292 / DB-580).
# Idempotente por `integration_key`.
#
# Sem estas quatro linhas nenhuma `Remuneration` da classe **EST** tem tipo a
# que apontar, e o faturamento de operação estruturada sai zerado sem ninguém
# perceber. As chaves `fomento`, `comissaria`, `intercompany` e
# `auto_liquidavel` são CONTRATO.
#
# **Ponto de entrada individual** — ver a nota em `user_types.rb`.
puts '🏗  Tipos de operação estruturada (DB-292)…'
Seeds::Reference::Runner.call_one!('Seeds::Reference::StructuredOperationTypes', io: $stdout)
