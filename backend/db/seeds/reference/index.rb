# frozen_string_literal: true

# S3 / **OPS-540** — o ponto de entrada dos seeds de REFERÊNCIA.
#
# Um `load` só, para sempre. A lista de catálogos é dado
# (`Seeds::Reference::Runner::CATALOGS`) e a lógica mora em
# `app/services/seeds/reference/`, onde pode ser testada e chamada de dentro do
# app — este arquivo existe apenas para que `db/seeds.rb` e o `rake` cheguem lá
# pelo mesmo caminho.
#
# **Idempotente**: rodar de novo não duplica linha nem desfaz o que o usuário
# arrumou na tela. É essa propriedade que o torna seguro no passo de deploy
# (`rake reference:seed`).
Seeds::Reference::Runner.call!(io: $stdout)
