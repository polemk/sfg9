# frozen_string_literal: true

require 'rails_helper'

# S2 / BE-413 — as opções encadeadas do formulário de endereço.
#
# No legado `state_select`/`city_select` existiam no controller e **não tinham
# rota**. O select de estado nunca era preenchido.
RSpec.describe 'Estados por país', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:user) { create(:user, :colaborador) }

  it 'devolve as 27 unidades federativas do Brasil' do
    get '/api/v1/countries/BR/states', headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    estados = JSON.parse(response.body)['states']
    expect(estados.size).to eq(27)
    expect(estados.map { |e| e['code'] }).to include('SP', 'RJ', 'DF')
  end

  it 'aceita o código em minúsculas' do
    get '/api/v1/countries/br/states', headers: auth_headers(user)
    expect(JSON.parse(response.body)['states'].size).to eq(27)
  end

  # País sem subdivisão cadastrada **não é erro**: é lista vazia. Devolver 404
  # faria o formulário mostrar uma falha onde a resposta correta é "não há o que
  # escolher".
  it 'país sem lista devolve vazio, não 404' do
    get '/api/v1/countries/PT/states', headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['states']).to eq([])
  end

  it 'exige sessão' do
    get '/api/v1/countries/BR/states'
    expect(response).to have_http_status(:unauthorized)
  end
end
