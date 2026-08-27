# frozen_string_literal: true

# S12 / OPS-330 — seed de REFERÊNCIA dos contratos. Idempotente.
#
# Publica a **versão 1** dos Termos de Uso e da Política de Privacidade a partir
# de `db/seed_assets/contracts/`, e **não cria nenhum `ContractDeal`**.
#
# O `tasks.md` desta fatia nomeia `db/seeds/contracts.rb`; o arquivo vive em
# `db/seeds/reference/` porque é onde o carregador único (OPS-540) procura, e
# inventar um segundo caminho de seed é exatamente o que aquela decisão proíbe.
#
# **Ponto de entrada individual** — casca fina sobre `Seeds::Reference::Runner`.
puts '📜 Contratos — ToU e Política de Privacidade (OPS-330)…'
Seeds::Reference::Runner.call_one!('Seeds::Reference::Contracts', io: $stdout)
