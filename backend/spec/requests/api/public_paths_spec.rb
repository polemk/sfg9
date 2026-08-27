# frozen_string_literal: true

require 'rails_helper'

# Achado da varredura de resíduos do trim (R-01, 26/08/2026).
#
# A allowlist de `public_paths` do `Api::Root` — as rotas que **pulam
# autenticação** — tinha três entradas de webhook que não existem mais:
# `messages-upsert`, `send-message` e `messages-update`.
#
# Enquanto a rota não existe, a entrada é inofensiva: dá 404 antes de qualquer
# coisa. O problema é o dia em que alguém redeclarar um `resource` com esse nome
# — ele nasce **sem autenticação**, e ninguém vai procurar o motivo na allowlist.
RSpec.describe 'Api::Root — allowlist de rotas públicas' do
  # As rotas de webhook realmente declaradas em `whats/v1/webhooks.rb`.
  DECLARADOS = %w[connection-update logout-instance qrcode-updated config].freeze

  let(:allowlist) do
    Api::Root.new
    src = File.read(Rails.root.join('app/controllers/api/root.rb'))
    src.scan(%r{\^/whats/v1/webhooks/([a-z-]+)/\?\$}).flatten
  end

  it 'não libera nenhum webhook que não esteja declarado' do
    sobrando = allowlist - DECLARADOS
    expect(sobrando).to be_empty,
                        "allowlist libera rota inexistente: #{sobrando.join(', ')} — " \
                        'se alguém redeclarar esse `resource`, ele nasce sem autenticação'
  end

  it 'os webhooks declarados batem com o que o arquivo de webhooks expõe' do
    fonte = File.read(Rails.root.join('app/controllers/api/whats/v1/webhooks.rb'))
    reais = fonte.scan(/resource ['"]([a-z-]+)['"]/).flatten
    expect(reais.sort).to eq(DECLARADOS.sort),
                          'a lista deste spec saiu de sincronia com os webhooks de verdade'
  end
end
