# frozen_string_literal: true

# Seed de REFERÊNCIA do catálogo de permissões. Idempotente.
#
# Das 17 abilities do legado voltam as **7 com efeito real** (DEC-108) — as que
# têm pelo menos um call site fora do factory e dos seeds. As outras 10 têm zero
# consumidor, verificado uma a uma, e ficam descartadas.
#
# **Ponto de entrada individual** — ver a nota em `user_types.rb`. O carregador
# único é `Seeds::Reference::Runner` (OPS-540); este arquivo é casca fina sobre
# ele e existe porque o `parity-ledger` aponta para ele (DB-008, OPS-009).
puts '🔐 Catálogo de permissões (DEC-108)…'
Seeds::Reference::Runner.call_one!('Seeds::Reference::Permissions', io: $stdout)
