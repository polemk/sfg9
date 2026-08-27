# frozen_string_literal: true

require 'rails_helper'

# S3 / OPS-057 (Lacuna L-11) — as UFs como CADASTRO, não geocodificação.
RSpec.describe 'UFs do Brasil', type: :request do
  before { UserType.seed_default_types! }

  let(:usuario) { create(:user, :colaborador) }

  it 'devolve as 27 unidades federativas' do
    get '/api/v1/br_states', headers: auth_headers(usuario)
    expect(response).to have_http_status(:ok)
    estados = JSON.parse(response.body)['states']
    expect(estados.size).to eq(27)
    expect(estados.map { |e| e['code'] }).to include('SP', 'RJ', 'DF', 'AC')
  end

  it 'filtra por sigla e por nome, ignorando acento' do
    get '/api/v1/br_states', params: { q: 'ceara' }, headers: auth_headers(usuario)
    expect(JSON.parse(response.body)['states'].map { |e| e['code'] }).to eq(['CE'])

    get '/api/v1/br_states', params: { q: 'grande' }, headers: auth_headers(usuario)
    expect(JSON.parse(response.body)['states'].map { |e| e['code'] }).to contain_exactly('RN', 'RS')
  end

  # "sp" casa também com "E-sp-írito Santo". Excluir seria quebrar a busca por
  # nome; devolver o ES antes do SP faria o campo parecer defeituoso.
  it 'a sigla EXATA vem primeiro' do
    get '/api/v1/br_states', params: { q: 'sp' }, headers: auth_headers(usuario)
    codigos = JSON.parse(response.body)['states'].map { |e| e['code'] }
    expect(codigos.first).to eq('SP')
    expect(codigos).to include('ES')
  end

  it 'exige sessão' do
    get '/api/v1/br_states'
    expect(response).to have_http_status(:unauthorized)
  end

  # A lista é UMA. Duas listas de 27 UFs divergem na primeira correção de acento.
  it 'é a MESMA lista de `Countries::BRAZILIAN_STATES`' do
    expect(Api::V1::BrStates::UF).to equal(Api::V1::Countries::BRAZILIAN_STATES)
    expect(Api::V1::BrStates::CODES).to eq(Api::V1::Countries::BRAZILIAN_STATES.map { |uf| uf[:code] })
  end

  # `geocoder` e `city-state` não são portados: no legado o geocoder rodava com
  # timeout de ~3h20 e sem cache para preencher dois campos de formulário.
  it 'o `geocoder` NÃO é portado' do
    expect(Rails.root.join('Gemfile').read).not_to match(/^\s*gem ['"]geocoder['"]/)
  end
end
