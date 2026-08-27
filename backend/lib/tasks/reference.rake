# frozen_string_literal: true

# S3 / **OPS-540** — os seeds de REFERÊNCIA, aplicados pelo deploy.
#
# `rake reference:seed` é **idempotente** e roda em qualquer ambiente, inclusive
# produção: é essa propriedade que o torna seguro como passo fixo de deploy,
# logo depois de `db:migrate`. Rodar de novo não duplica linha nem desfaz
# alteração feita pelo usuário na tela.
#
#   bin/rails db:migrate && bin/rails reference:seed
#
# **Não confundir com `rake demo:seed`** (S20), que semeia a base de
# demonstração e NÃO roda no cutover real. A separação é deliberada: no legado
# os dois estavam misturados, a ponto de o bloco de empresas estar marcado no
# próprio código como "seed feito somente para vídeo de aprovação".
#
# ### Como a sua fatia pluga o catálogo dela
#
# 1. `app/services/seeds/reference/<seu_catalogo>.rb`, herdando de
#    `Seeds::Reference::Catalog`;
# 2. uma linha em `Seeds::Reference::Runner::CATALOGS`.
#
# Nada mais. Não crie uma segunda rake nem um segundo `load`.
namespace :reference do
  desc 'Semeia os catálogos de REFERÊNCIA (idempotente — pode rodar no deploy)'
  task seed: :environment do
    relatorios = Seeds::Reference::Runner.call!(io: $stdout)
    pulados = relatorios.select(&:skipped?)
    puts
    puts "#{relatorios.size - pulados.size} catálogo(s) aplicado(s), #{pulados.size} pulado(s)."
    puts 'Rode de novo quando a fatia dona entregar — é idempotente.' if pulados.any?
  end

  desc 'Mostra quais catálogos de referência já podem rodar (não escreve nada)'
  task status: :environment do
    puts 'Catálogos de referência:'
    Seeds::Reference::Runner.status
  end
end
