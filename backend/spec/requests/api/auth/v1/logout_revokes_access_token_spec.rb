# frozen_string_literal: true

require 'rails_helper'

# D-QA-02 — «Sair» não revogava o access token.
#
# O logout SEMPRE fez a sua parte: `Auth::SessionsService#revoke_token` grava o
# `jti` na `jwt_denylist`, e `Auth::TokenService.revoked?` respondia `true` logo
# depois. O que faltava era alguém PERGUNTAR. No gate central
# (`api/root.rb`) o `Warden::JWTAuth::TokenDecoder` roda primeiro, não consulta a
# denylist, e — por estar sempre definido — vencia o `||=` que escolheria o
# `Auth::TokenService#decode_token`, o único dos dois que checa revogação. O
# mesmo par de linhas existia em `api/v1/defaults.rb#current_user`.
#
# Efeito medido: depois de «Sair», o MESMO access token continuava valendo até
# expirar sozinho — até 15 min (`ACCESS_TTL`) de sessão viva num computador
# compartilhado depois de a pessoa achar que saiu.
#
# Este spec falha sem o conserto: sem a linha `payload = nil if payload &&
# Auth::TokenService.revoked?(payload)`, o terceiro pedido responde 200.
RSpec.describe 'D-QA-02 — «Sair» revoga o access token', type: :request do
  let(:user) { create(:user) }

  # `GET /api/v1/permissions/me` é o endpoint autenticado mais barato que existe:
  # exige sessão (`authenticate_user!`), não exige papel nenhum e não depende de
  # dado semeado. Serve como "o token ainda vale?" sem arrastar cenário junto.
  let(:endpoint) { '/api/v1/permissions/me' }

  def bearer(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  it 'aceita o token antes do «Sair» e recusa o MESMO token depois' do
    tokens = Auth::TokenService.new(user).generate_tokens
    access = tokens[:token]

    # 1) antes: a sessão vale.
    get endpoint, headers: bearer(access)
    expect(response).to have_http_status(200)

    # 2) «Sair».
    delete '/auth/v1/sessions/logout', headers: bearer(access)
    expect(response).to have_http_status(200)

    # O logout de fato gravou o `jti` — se esta expectativa cair, o defeito é
    # outro (a revogação em si), e não o gate que deixa de perguntar.
    payload = Warden::JWTAuth::TokenDecoder.new.call(access)
    expect(Auth::TokenService.revoked?(payload)).to be(true),
                                                   'o logout não gravou o jti na denylist — defeito diferente do D-QA-02'

    # 3) depois: o MESMO token não vale mais. É esta linha que falhava antes do
    # conserto — respondia 200.
    get endpoint, headers: bearer(access)
    expect(response).to have_http_status(401)
  end

  # A pergunta que mais importa: o conserto derruba SÓ o token revogado.
  # A versão que quebrou o app em 26/08 rejeitava tudo, inclusive token
  # recém-emitido; este exemplo é o portão contra essa regressão.
  it 'não afeta um login novo: token emitido depois do «Sair» continua valendo' do
    antigo = Auth::TokenService.new(user).generate_tokens[:token]

    delete '/auth/v1/sessions/logout', headers: bearer(antigo)
    expect(response).to have_http_status(200)

    novo = Auth::TokenService.new(user).generate_tokens[:token]

    get endpoint, headers: bearer(novo)
    expect(response).to have_http_status(200)

    # E o antigo segue barrado, para não passar por acidente de cache.
    get endpoint, headers: bearer(antigo)
    expect(response).to have_http_status(401)
  end

  # O token de OUTRA pessoa não pode cair junto: a denylist é por `jti`, não por
  # usuário. Se algum dia alguém trocar a consulta por `sub`, este exemplo cai.
  it 'o «Sair» de um usuário não derruba a sessão de outro' do
    outro = create(:user)
    token_do_outro = Auth::TokenService.new(outro).generate_tokens[:token]
    meu = Auth::TokenService.new(user).generate_tokens[:token]

    delete '/auth/v1/sessions/logout', headers: bearer(meu)
    expect(response).to have_http_status(200)

    get endpoint, headers: bearer(token_do_outro)
    expect(response).to have_http_status(200)
  end
end
