# frozen_string_literal: true

require 'rails_helper'

# S13 / OPS-480, BE-457 — DEC-46: a consulta volta, **com teto por usuário/dia**.
#
# O que estes exemplos travam: a integração é **paga por consulta** e o custo é do
# cliente. Um laço acidental na tela vira fatura, e o legado não tinha teto nenhum.
RSpec.describe 'API::V1::CnpjLookup' do
  # `Rails.cache` é `:null_store` em teste. Cache e cota vivem no cache, então sem
  # trocar o store estes exemplos testariam o nada.
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  let(:user) { create(:user, :colaborador) }
  let(:cnpj) { '19131243000197' } # CNPJ real e público (Instituto Nacional de TI)

  def stub_receita(body, status: 200)
    stub_request(:get, %r{receitaws\.com\.br/v1/cnpj/#{cnpj}})
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  let(:payload) do
    {
      status: 'OK', cnpj: '19.131.243/0001-97', nome: 'INSTITUTO NACIONAL',
      fantasia: 'IN', situacao: 'ATIVA', cep: '01.310-000', logradouro: 'AV PAULISTA',
      numero: '1000', bairro: 'BELA VISTA', municipio: 'SAO PAULO', uf: 'SP',
      atividade_principal: [{ text: 'Desenvolvimento de software', code: '62.01-5-01' }]
    }
  end

  before { Credential.create!(name: 'ReceitaWS', provider: 'receitaws', api_key: 'tok-teste') }

  it 'devolve o cadastro em forma estável, sem repassar o corpo cru do terceiro' do
    stub_receita(payload)

    get "/api/v1/cnpj/#{cnpj}", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)['data']
    expect(data['name']).to eq('INSTITUTO NACIONAL')
    expect(data['city']).to eq('SAO PAULO')
    expect(data['zip_code']).to eq('01310000')
    expect(data['main_activity']).to eq('Desenvolvimento de software')
  end

  it 'não repete a chamada quando o CNPJ já está em cache — cada consulta é dinheiro' do
    request_stub = stub_receita(payload)

    2.times { get "/api/v1/cnpj/#{cnpj}", headers: auth_headers(user) }

    expect(request_stub).to have_been_requested.once
  end

  it 'para no teto diário do usuário (DEC-46) em vez de virar fatura' do
    allow(Sfg::ReceitaWs::LookupService).to receive(:daily_limit).and_return(2)
    # CNPJs distintos e válidos, para não cair no cache.
    %w[19131243000197 11222333000181 34028316000103].each_with_index do |doc, index|
      stub_request(:get, %r{receitaws\.com\.br/v1/cnpj/#{doc}})
        .to_return(status: 200, body: payload.merge(cnpj: doc).to_json,
                   headers: { 'Content-Type' => 'application/json' })
      get "/api/v1/cnpj/#{doc}", headers: auth_headers(user)

      if index < 2
        expect(response).to have_http_status(:ok)
      else
        expect(response).to have_http_status(:too_many_requests)
        expect(JSON.parse(response.body)['message']).to include('limite de 2 consultas')
      end
    end
  end

  it 'degrada quando a integração cai — NÃO devolve 500 e não impede o cadastro manual' do
    stub_request(:get, %r{receitaws\.com\.br/v1/cnpj/#{cnpj}}).to_timeout

    get "/api/v1/cnpj/#{cnpj}", headers: auth_headers(user)

    expect(response).to have_http_status(:service_unavailable)
    expect(JSON.parse(response.body)['message']).to include('manualmente')
  end

  it 'trata CNPJ inexistente, que a ReceitaWS devolve como 200 com status ERROR' do
    stub_receita({ status: 'ERROR', message: 'CNPJ inválido' })

    get "/api/v1/cnpj/#{cnpj}", headers: auth_headers(user)

    # Olhar só o código HTTP faria "não encontrado" chegar à tela como sucesso vazio.
    expect(response).to have_http_status(:not_found)
  end

  it 'recusa CNPJ com dígito verificador errado ANTES de gastar uma consulta' do
    request_stub = stub_request(:get, %r{receitaws\.com\.br}).to_return(status: 200, body: '{}')

    get '/api/v1/cnpj/11111111111111', headers: auth_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(request_stub).not_to have_been_requested
  end

  it 'sem chave configurada responde indisponível — e o app continua de pé' do
    Credential.delete_all
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('RECEITAWS_TOKEN').and_return(nil)

    get "/api/v1/cnpj/#{cnpj}", headers: auth_headers(user)

    expect(response).to have_http_status(:service_unavailable)
  end

  it 'exige sessão' do
    get "/api/v1/cnpj/#{cnpj}"
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'GET /api/v1/cnpj' do
    it 'diz se a integração está ligada e quanto resta da cota' do
      get '/api/v1/cnpj', headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['enabled']).to be(true)
      expect(body['remaining_quota']).to eq(body['daily_limit'])
    end
  end
end
