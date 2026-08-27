# frozen_string_literal: true

require 'rails_helper'

# S12 / DEC-38 — **o gate que nunca existiu**.
#
# `contracts_controller.rb` do legado tem 101 linhas e ZERO `before_action`,
# `may?`, `admin?`, `og?` ou `authorize`; as rotas não têm constraint
# (`routes.rb:30-31`) e o `create` só carimba `creator` e salva. Hoje **qualquer
# autenticado publica os Termos de Uso** — e como o vigente é o de maior versão,
# o texto que todo mundo aceita passa a ser o dele.
#
# Este spec prova o gate **dos dois lados**: quem pode e quem não pode.
RSpec.describe 'Versões de contrato — publicação (DEC-38)', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og) }
  let(:admin) { create(:user, :admin) }
  let(:gerente) { create(:user, :gerente) }
  let(:colaborador) { create(:user, :colaborador) }

  let(:payload) do
    { kind: Contract::KIND_TERMS_OF_USE, title: 'Termos de Uso', description: '<p>Novo texto.</p>' }
  end

  describe 'POST /api/v1/contract_versions — quem PODE' do
    it 'OG publica' do
      post '/api/v1/contract_versions', params: payload, headers: auth_headers(og)
      expect(response).to have_http_status(:created)
      expect(Contract.last.creator_id).to eq(og.id)
    end

    it 'Admin publica' do
      post '/api/v1/contract_versions', params: payload, headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
    end
  end

  describe 'POST /api/v1/contract_versions — quem NÃO pode' do
    it 'Gerente recebe 403 DO SERVIDOR, não só ausência de botão' do
      post '/api/v1/contract_versions', params: payload, headers: auth_headers(gerente)
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['code']).to eq('ROLE_REQUIRED')
      expect(Contract.count).to eq(0)
    end

    it 'Colaborador recebe 403' do
      post '/api/v1/contract_versions', params: payload, headers: auth_headers(colaborador)
      expect(response).to have_http_status(:forbidden)
      expect(Contract.count).to eq(0)
    end

    it 'sem sessão, 401' do
      post '/api/v1/contract_versions', params: payload
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'a matriz diz exatamente isso' do
    it 'contract_versions: OG e Admin CRUD, Gerente e Colaborador nada' do
      %i[create read update destroy].each do |acao|
        expect(Authorization::Matrix.allow?('og', 'contract_versions', acao)).to be(true)
        expect(Authorization::Matrix.allow?('admin', 'contract_versions', acao)).to be(true)
        expect(Authorization::Matrix.allow?('gerente', 'contract_versions', acao)).to be(false)
        expect(Authorization::Matrix.allow?('colaborador', 'contract_versions', acao)).to be(false)
      end
    end

    it 'o recurso `contracts` (ler e aceitar) fica como a matriz aprovou: R para os quatro' do
      %w[og admin gerente colaborador].each do |papel|
        expect(Authorization::Matrix.allow?(papel, 'contracts', :read)).to be(true)
      end
    end
  end

  # -------------------------------------------------------------------
  # O mass assignment que vai junto (DEC-38)
  # -------------------------------------------------------------------
  describe 'mass assignment de `id` e `version` fechado' do
    it '`version` no payload é ignorado — a numeração é do servidor' do
      post '/api/v1/contract_versions', params: payload.merge(version: 999), headers: auth_headers(og)
      expect(Contract.last.version).to eq(1)
    end

    it '`id` no payload é ignorado — `create` não sobrescreve outra linha' do
      existente = create(:contract, creator: og)
      post '/api/v1/contract_versions', params: payload.merge(id: existente.id), headers: auth_headers(og)

      expect(response).to have_http_status(:created)
      expect(Contract.count).to eq(2)
      expect(existente.reload.version).to eq(1)
    end

    it '`creator_id` no payload é ignorado — o autor é o da sessão' do
      post '/api/v1/contract_versions', params: payload.merge(creator_id: colaborador.id),
                                        headers: auth_headers(admin)
      expect(Contract.last.creator_id).to eq(admin.id)
    end

    it 'tipo fora do catálogo fechado é recusado (BE-339)' do
      post '/api/v1/contract_versions', params: payload.merge(kind: 'Contrato de usuário'),
                                        headers: auth_headers(og)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # -------------------------------------------------------------------
  # BE-338 — o prefill, e o primeiro contrato de um tipo
  # -------------------------------------------------------------------
  describe 'GET /api/v1/contract_versions/prefill' do
    it 'o PRIMEIRO contrato de um tipo abre vazio, com next_version = 1' do
      get '/api/v1/contract_versions/prefill', params: { kind: 'termos-de-uso' }, headers: auth_headers(og)

      corpo = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(corpo['next_version']).to eq(1)
      expect(corpo['title']).to eq('')
      expect(corpo['description_html']).to eq('')
    end

    it 'a partir da segunda, pré-preenche com a anterior' do
      contrato = create(:contract, creator: og, title: 'Termos v1')
      contrato.description = '<p>anterior</p>'
      contrato.save!

      get '/api/v1/contract_versions/prefill', params: { kind: Contract::KIND_TERMS_OF_USE },
                                               headers: auth_headers(og)

      corpo = JSON.parse(response.body)
      expect(corpo['next_version']).to eq(2)
      expect(corpo['title']).to eq('Termos v1')
      expect(corpo['description_html']).to include('anterior')
    end

    it 'Gerente não alcança nem o prefill' do
      get '/api/v1/contract_versions/prefill', params: { kind: 'termos-de-uso' }, headers: auth_headers(gerente)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # DEC-80 mitigação 2 — o AVISO ao editar contrato com aceites
  # -------------------------------------------------------------------
  describe 'GET /api/v1/contract_versions/:id/impact' do
    it 'diz quantos aceites ficariam com hash divergente' do
      contrato = create(:contract, creator: og)
      contrato.description = '<p>texto original</p>'
      contrato.save!
      create(:contract_deal, contract: contrato, user: colaborador)
      create(:contract_deal, contract: contrato, user: gerente)

      get "/api/v1/contract_versions/#{contrato.id}/impact", headers: auth_headers(og)
      expect(JSON.parse(response.body)['divergent_count']).to eq(0)

      contrato.description = '<p>texto alterado</p>'
      contrato.save!

      get "/api/v1/contract_versions/#{contrato.id}/impact", headers: auth_headers(og)
      corpo = JSON.parse(response.body)
      expect(corpo['accepted_count']).to eq(2)
      expect(corpo['divergent_count']).to eq(2)
      expect(corpo['is_current']).to be(true)
    end
  end

  describe 'DELETE /api/v1/contract_versions/:id' do
    it 'versão com aceite gravado NÃO é removida — apagaria a prova junto' do
      contrato = create(:contract, creator: og)
      create(:contract_deal, contract: contrato, user: colaborador)

      delete "/api/v1/contract_versions/#{contrato.id}", headers: auth_headers(og)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['code']).to eq('CONTRACT_HAS_ACCEPTANCES')
      expect(Contract.count).to eq(1)
    end

    it 'versão sem aceite é removida' do
      contrato = create(:contract, creator: og)
      delete "/api/v1/contract_versions/#{contrato.id}", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
    end

    it 'Colaborador não remove' do
      contrato = create(:contract, creator: og)
      delete "/api/v1/contract_versions/#{contrato.id}", headers: auth_headers(colaborador)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/contract_versions' do
    it 'histórico completo, da mais recente para a mais antiga' do
      3.times { |i| create(:contract, creator: og, title: "v#{i}") }

      get '/api/v1/contract_versions', headers: auth_headers(admin)

      versoes = JSON.parse(response.body).map { |c| c['version'] }
      expect(versoes).to eq([3, 2, 1])
      expect(response.headers['X-Total-Count']).to eq('3')
    end

    it 'filtro por tipo fora do catálogo devolve VAZIO, não a base inteira' do
      create(:contract, creator: og)
      get '/api/v1/contract_versions', params: { kind: 'inexistente' }, headers: auth_headers(og)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'a busca por título ignora acento' do
      contrato = create(:contract, creator: og, title: 'Termos de Adesão')
      get '/api/v1/contract_versions', params: { q: 'adesao' }, headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |c| c['id'] }).to eq([contrato.id])
    end

    it 'Gerente não lista' do
      get '/api/v1/contract_versions', headers: auth_headers(gerente)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/contract_versions/:id/proof — OPS-333' do
    it 'exporta CSV com o texto integral, e só para quem publica' do
      contrato = create(:contract, creator: og)
      contrato.description = '<p>texto probatório</p>'
      contrato.save!
      create(:contract_deal, contract: contrato, user: colaborador)

      get "/api/v1/contract_versions/#{contrato.id}/proof", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('texto probatório')

      get "/api/v1/contract_versions/#{contrato.id}/proof", headers: auth_headers(colaborador)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
