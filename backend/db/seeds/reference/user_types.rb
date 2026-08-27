# frozen_string_literal: true

# Seed de REFERÊNCIA — os 4 papéis do Safegold na escala do ai9
# (DEC-41: OG=1, Admin=2, Gerente=3, Colaborador=4; menor = mais poder).
#
# Idempotente: rodar duas vezes não duplica nem reescreve papel já atribuído.
#
# **Ponto de entrada individual.** A lógica mora em
# `app/services/seeds/reference/user_types.rb`, e quem orquestra é o carregador
# ÚNICO `Seeds::Reference::Runner` (OPS-540) — `db/seeds.rb` e `rake
# reference:seed` passam por ele, não por este arquivo. Este arquivo continua
# existindo porque o `parity-ledger` aponta para ele (DB-006, DB-502) e porque
# rodar um catálogo isolado é útil no console.
puts '👥 Papéis do Safegold (DEC-41)…'
Seeds::Reference::Runner.call_one!('Seeds::Reference::UserTypes', io: $stdout)
