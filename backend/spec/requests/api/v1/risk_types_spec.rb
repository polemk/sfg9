# frozen_string_literal: true

require 'rails_helper'

# S5 / BE-278, BE-279, FE-279 — **os dois catálogos de tipo do bloco de risco**.
#
# Um arquivo para os dois de propósito: no legado eles eram o mesmo cadastro com
# **gates de papel diferentes** e **listas diferentes** (um listava só ativos, o
# outro listava tudo), e a assimetria só ficou visível quando alguém os pôs lado
# a lado. É o que este arquivo faz.
RSpec.describe 'API V1 Risk types', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, user_type: UserType.og) }
  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  # ---------------------------------------------------------------------------
  # BE-278 — tipos de limite
  # ---------------------------------------------------------------------------
  describe 'risk_operation_types' do
    it 'creates the type AND its subtypes in one call' do
      post '/api/v1/risk_operation_types',
           params: { title: 'Novo Com Pré', has_pre_faturamento: true },
           headers: auth_headers(gerente), as: :json

      expect(response).to have_http_status(201)
      corpo = JSON.parse(response.body)
      expect(corpo['integration_key']).to eq('novo_com_pre')
      expect(corpo['subtypes'].size).to eq(2)
      expect(corpo['subtypes'].count { |s| s['is_default_for_type'] }).to eq(1)
    end

    it 'creates ONE subtype when there is no pre-billing' do
      post '/api/v1/risk_operation_types', params: { title: 'Novo Sem Pré' },
                                           headers: auth_headers(gerente), as: :json

      expect(JSON.parse(response.body)['subtypes'].size).to eq(1)
    end

    it 'REFUSES to change has_pre_faturamento on update — it is not in the contract' do
      tipo = create(:risk_operation_type, title: 'Imutável')

      put "/api/v1/risk_operation_types/#{tipo.id}",
          params: { has_pre_faturamento: true, title: 'Imutável Renomeado' },
          headers: auth_headers(gerente), as: :json

      expect(response).to have_http_status(200)
      # O título mudou; a flag NÃO — e a chave continua congelada (DC-22).
      expect(tipo.reload.title).to eq('Imutável Renomeado')
      expect(tipo.has_pre_faturamento).to be(false)
      expect(tipo.integration_key).to eq('imutavel')
    end

    it 'answers 404 (not 500) for a nonexistent id' do
      get "/api/v1/risk_operation_types/#{SecureRandom.uuid}", headers: auth_headers(gerente)
      expect(response).to have_http_status(404)
    end

    it 'answers 422 REAL when the type is in use by a control (D-24)' do
      projeto = create_project_with_owner(gerente, slug: 'tp-a', name: 'Tipos A')
      empresa = create(:company, project: projeto)
      tipo = create(:risk_operation_type, title: 'Em Uso')
      create(:risk_control, project: projeto, company: empresa, risk_operation_type: tipo)

      delete "/api/v1/risk_operation_types/#{tipo.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(RiskOperationType.exists?(tipo.id)).to be(true)
    end

    it 'answers 422 for a seeded type' do
      tipo = create(:risk_operation_type, :semeado, title: 'Semeado')
      delete "/api/v1/risk_operation_types/#{tipo.id}", headers: auth_headers(gerente)
      expect(response).to have_http_status(422)
    end

    it 'lets the Colaborador READ but not WRITE (DEC-18.4)' do
      get '/api/v1/risk_operation_types', headers: auth_headers(colaborador)
      expect(response).to have_http_status(200)

      post '/api/v1/risk_operation_types', params: { title: 'Do colaborador' },
                                           headers: auth_headers(colaborador), as: :json
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body)['code']).to eq('ROLE_REQUIRED')
    end

    it 'requires a session — the legacy answered to ANONYMOUS (D-23)' do
      get '/api/v1/risk_operation_types'
      expect(response).to have_http_status(401)
    end
  end

  # ---------------------------------------------------------------------------
  # BE-279 — tipos de movimentação
  # ---------------------------------------------------------------------------
  describe 'risk_movement_types' do
    it 'creates a movement type with the credit sign' do
      post '/api/v1/risk_movement_types', params: { title: 'Tarifa Nova', credit_type: 'D' },
                                          headers: auth_headers(gerente), as: :json

      expect(response).to have_http_status(201)
      corpo = JSON.parse(response.body)
      expect(corpo['credit_type']).to eq('D')
      expect(corpo['credit_type_description']).to eq('Débito')
      expect(corpo['integration_key']).to eq('tarifa_nova')
    end

    it 'refuses a credit_type outside C/D with 400, at the contract boundary' do
      post '/api/v1/risk_movement_types', params: { title: 'Errado', credit_type: 'X' },
                                          headers: auth_headers(gerente), as: :json
      expect(response).to have_http_status(400)
    end

    it 'offers the is_active filter that the legacy screen did not have' do
      create(:risk_movement_type, title: 'Ativo Mov', credit_type: 'D')
      create(:risk_movement_type, title: 'Inativo Mov', credit_type: 'C', is_active: false)

      get '/api/v1/risk_movement_types', params: { active: true }, headers: auth_headers(gerente)
      titulos = JSON.parse(response.body).map { |t| t['title'] }
      expect(titulos).to include('Ativo Mov')
      expect(titulos).not_to include('Inativo Mov')

      get '/api/v1/risk_movement_types', headers: auth_headers(gerente)
      expect(JSON.parse(response.body).map { |t| t['title'] }).to include('Inativo Mov')
    end

    it 'answers 422 when the destroy FAILS — the legacy answered :ok on the error branch' do
      tipo = create(:risk_movement_type, :semeado, title: 'Semeado Mov', credit_type: 'D')

      delete "/api/v1/risk_movement_types/#{tipo.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(RiskMovementType.exists?(tipo.id)).to be(true)
    end

    it 'has the SAME role gate as the sibling screen — the legacy asymmetry is gone (FE-279)' do
      # Colaborador lê os dois e não escreve em nenhum.
      get '/api/v1/risk_movement_types', headers: auth_headers(colaborador)
      expect(response).to have_http_status(200)

      post '/api/v1/risk_movement_types', params: { title: 'X', credit_type: 'D' },
                                          headers: auth_headers(colaborador), as: :json
      expect(response).to have_http_status(403)
    end

    it 'lets OG write, like the sibling screen (C3 — the other side)' do
      post '/api/v1/risk_movement_types', params: { title: 'Do OG', credit_type: 'C' },
                                          headers: auth_headers(og), as: :json
      expect(response).to have_http_status(201)
    end
  end

  # ---------------------------------------------------------------------------
  # Contrato C1 — catálogo global não é escopado
  # ---------------------------------------------------------------------------
  describe 'contract C1 — global catalogs are NOT project scoped' do
    it 'answers the two catalogs without any project header' do
      create(:risk_operation_type, title: 'Global 1')
      create(:risk_movement_type, title: 'Global 2', credit_type: 'D')

      # Sem `X-Project-Id` e sem participação nenhuma.
      solto = create(:user, user_type: UserType.colaborador)

      get '/api/v1/risk_operation_types', headers: auth_headers(solto)
      expect(response).to have_http_status(200)

      get '/api/v1/risk_movement_types', headers: auth_headers(solto)
      expect(response).to have_http_status(200)
    end
  end
end
