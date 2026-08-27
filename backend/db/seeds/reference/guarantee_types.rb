# frozen_string_literal: true

# Seed de REFERÊNCIA dos **tipos de garantia** (DB-558 / DEC-86). Idempotente.
#
# Sem estas linhas o select de garantias do projeto sobe VAZIO — que é
# literalmente o estado do legado, onde a tabela existe desde 2022 e nenhum seed
# a popula. Os tipos nascem marcados `is_provisional`: são suposição, e a lista
# definitiva é do cliente.
#
# **Ponto de entrada individual** — ver a nota em `user_types.rb`.
puts '🛡  Tipos de garantia (DEC-86 — provisórios)…'
Seeds::Reference::Runner.call_one!('Seeds::Reference::GuaranteeTypes', io: $stdout)
