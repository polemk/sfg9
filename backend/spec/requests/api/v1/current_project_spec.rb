# frozen_string_literal: true

require 'rails_helper'

# S2 / BE-412 — o seletor de projeto. Contrato C1 pela porta da frente.
RSpec.describe 'Seletor de projeto', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:user) { create(:user, :gerente) }
  let(:outro) { create(:user, :gerente) }

  describe 'GET /api/v1/current_project' do
    # 6.2.1 — troca SÓ entre projetos com participação.
    it 'lista apenas os projetos em que o usuário participa' do
      meu = create_project_with_owner(user, name: 'Meu')
      create_project_with_owner(outro, name: 'Alheio')

      get '/api/v1/current_project', headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['projects'].map { |p| p['id'] }).to eq([meu.id])
    end

    it 'sem participação nenhuma, devolve lista vazia e corrente nulo' do
      get '/api/v1/current_project', headers: auth_headers(user)

      json = JSON.parse(response.body)
      expect(json['projects']).to be_empty
      expect(json['current']).to be_nil
    end

    it 'com uma única participação, ela já é o projeto corrente' do
      meu = create_project_with_owner(user)

      get '/api/v1/current_project', headers: auth_headers(user)

      expect(JSON.parse(response.body).dig('current', 'id')).to eq(meu.id)
    end
  end

  describe 'PUT /api/v1/current_project' do
    it 'troca para um projeto com participação' do
      a = create_project_with_owner(user, name: 'A')
      b = create_project_with_owner(user, name: 'B')
      user.update!(current_project_id: a.id)

      put '/api/v1/current_project', params: { project_id: b.id }, headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(user.reload.current_project_id).to eq(b.id)
    end

    # 6.2.2 — a condição 2 do DC-08. Distinguir 403 de 404 transformaria o
    # seletor num oráculo de existência de ids.
    it 'projeto inexistente e projeto sem participação respondem o MESMO status' do
      alheio = create_project_with_owner(outro)

      put '/api/v1/current_project', params: { project_id: alheio.id }, headers: auth_headers(user)
      sem_participacao = response.status

      put '/api/v1/current_project', params: { project_id: 999_999_999 }, headers: auth_headers(user)
      inexistente = response.status

      expect(sem_participacao).to eq(inexistente)
      expect(sem_participacao).to eq(404)
    end

    it 'não grava o projeto de outro usuário' do
      alheio = create_project_with_owner(outro)
      put '/api/v1/current_project', params: { project_id: alheio.id }, headers: auth_headers(user)

      expect(user.reload.current_project_id).to be_nil
    end
  end

  # 6.2.3 — regressão do D-28. O cookie `cached_info` do legado carregava o
  # tenant, era escrito pelos dois lados e não tinha nenhuma flag de segurança.
  describe 'nenhum cookie carrega o projeto corrente' do
    it 'a resposta não emite Set-Cookie com o projeto' do
      projeto = create_project_with_owner(user)
      put '/api/v1/current_project', params: { project_id: projeto.id }, headers: auth_headers(user)

      set_cookie = Array(response.headers['Set-Cookie']).join(';')
      expect(set_cookie).not_to include('cached_info')
      expect(set_cookie).not_to include(projeto.id.to_s)
    end

    it 'o valor vem do servidor: sem `X-Project-Id`, o corrente é o gravado' do
      a = create_project_with_owner(user, name: 'A')
      create_project_with_owner(user, name: 'B')
      user.update!(current_project_id: a.id)

      get '/api/v1/current_project', headers: auth_headers(user)

      expect(JSON.parse(response.body).dig('current', 'id')).to eq(a.id)
    end
  end
end
