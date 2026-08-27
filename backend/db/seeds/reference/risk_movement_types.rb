# frozen_string_literal: true

# Seed de REFERÊNCIA dos **tipos de movimentação de risco** (OPS-231 / OPS-232).
# Idempotente por `integration_key`.
#
# Três dos oito são FUNCIONAIS: `liberacao_do_recurso`, `valor_transferido` e
# `transferencia_recebida` são resolvidos por chave pelo próprio sistema (B-09),
# e sem eles a S7 não consegue lançar movimento nenhum.
#
# **Ponto de entrada individual** — ver a nota em `user_types.rb`.
puts '🔁 Movimentações de risco (OPS-231)…'
Seeds::Reference::Runner.call_one!('Seeds::Reference::RiskMovementTypes', io: $stdout)
