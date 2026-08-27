# frozen_string_literal: true

require 'rails_helper'

# Contrato **C3** no nível de requisição — o que a `Authorization::Hierarchy`
# promete, o endpoint cumpre.
#
# Este arquivo existe porque a trava de unidade não prova nada se o endpoint
# esquecer de chamá-la. Cada exemplo verifica os **dois** lados.
RSpec.describe 'Permissões, papéis e hierarquia', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og)          { create(:user, user_type: UserType.og) }
  let(:admin)       { create(:user, user_type: UserType.admin) }
  let(:gerente)     { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }
  let(:readonly_key) { 'user_is_readonly' }

  # 5.1.1
  describe 'PUT /api/v1/user_types/:id/permissions/:key' do
    it 'Admin NÃO edita permissão do papel OG — e EDITA a do Colaborador' do
      put "/api/v1/user_types/#{UserType.og.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'code')).to eq('HIERARCHY_LOCKED')
      # DEC-108 — o seed passou a criar a linha de default de cada papel, então
      # "a tabela do OG está vazia" deixou de ser a prova. A prova é que a
      # CHAVE que o Admin tentou ligar continua desligada para o OG.
      expect(UserTypePermission.granted
                               .joins(:permission)
                               .where(user_type: UserType.og, permissions: { key: readonly_key })).to be_empty

      put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(200)
      expect(UserTypePermission.granted
                               .joins(:permission)
                               .where(user_type: UserType.colaborador,
                                      permissions: { key: readonly_key })).to exist
    end

    # 5.1.2
    it 'Admin NÃO edita a permissão de outro Admin (lateral) — e o OG edita a de todos' do
      put "/api/v1/user_types/#{UserType.admin.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(403)

      put "/api/v1/user_types/#{UserType.admin.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(og)
      expect(response).to have_http_status(200)

      put "/api/v1/user_types/#{UserType.og.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(og)
      expect(response).to have_http_status(200)
    end

    # 5.1.3
    it 'Gerente NÃO alcança o endpoint de Permissões — e o Admin alcança' do
      put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(gerente)
      expect(response).to have_http_status(403)

      put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(200)
    end
  end

  describe 'GET /api/v1/permissions (catálogo)' do
    it 'Gerente NÃO lê o catálogo — e o Admin lê' do
      get '/api/v1/permissions', headers: auth_headers(gerente)
      expect(response).to have_http_status(403)

      get '/api/v1/permissions', headers: auth_headers(admin)
      expect(response).to have_http_status(200)
      keys = JSON.parse(response.body)['permissions'].map { |p| p['key'] }
      expect(keys).to include(readonly_key)
    end
  end

  describe 'GET /api/v1/permissions/me' do
    it 'qualquer sessão lê as PRÓPRIAS permissões' do
      get '/api/v1/permissions/me', headers: auth_headers(colaborador)
      expect(response).to have_http_status(200)
    end
  end

  # 3.9 / BE-018 / D-34 — o `:id` do usuário passa a mandar.
  describe 'PUT /api/v1/users/:id/permissions/:key' do
    it 'Admin NÃO concede permissão a um OG — e CONCEDE a um Colaborador' do
      put "/api/v1/users/#{og.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(admin)
      expect(response).to have_http_status(403)
      expect(UserPermission.where(user: og)).to be_empty

      put "/api/v1/users/#{colaborador.id}/permissions/#{readonly_key}",
          params: { granted: true, reason: 'auditoria' }, headers: auth_headers(admin)
      expect(response).to have_http_status(200)
      expect(colaborador.reload.readonly_access?).to be(true)
    end

    it 'o :id do alvo é respeitado: mudar o :id muda QUEM é afetado' do
      outro = create(:user, user_type: UserType.colaborador)

      put "/api/v1/users/#{colaborador.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(og)
      expect(colaborador.reload.readonly_access?).to be(true)
      expect(outro.reload.readonly_access?).to be(false)
    end

    it 'revogar volta atrás' do
      put "/api/v1/users/#{colaborador.id}/permissions/#{readonly_key}",
          params: { granted: true }, headers: auth_headers(og)
      expect(colaborador.reload.readonly_access?).to be(true)

      put "/api/v1/users/#{colaborador.id}/permissions/#{readonly_key}",
          params: { granted: false }, headers: auth_headers(og)
      expect(colaborador.reload.readonly_access?).to be(false)
    end
  end

  # 5.1.4 no endpoint
  describe 'GET /api/v1/users — filtro por hierarquia (BE-504)' do
    before do
      og
      admin
      gerente
      colaborador
    end

    it 'a lista do Gerente NÃO devolve OG nem Admin — e DEVOLVE Colaborador' do
      get '/api/v1/users', headers: auth_headers(gerente)
      expect(response).to have_http_status(200)
      ids = JSON.parse(response.body)['users'].map { |u| u['id'] }

      expect(ids).not_to include(og.id)
      expect(ids).not_to include(admin.id)
      expect(ids).to include(colaborador.id)
    end

    it 'a lista do OG devolve todos' do
      get '/api/v1/users', headers: auth_headers(og)
      ids = JSON.parse(response.body)['users'].map { |u| u['id'] }
      expect(ids).to include(og.id, admin.id, gerente.id, colaborador.id)
    end

    it 'Colaborador NÃO alcança a lista de usuários — e o Gerente alcança' do
      get '/api/v1/users', headers: auth_headers(colaborador)
      expect(response).to have_http_status(403)

      get '/api/v1/users', headers: auth_headers(gerente)
      expect(response).to have_http_status(200)
    end
  end

  describe 'GET /api/v1/user_types' do
    it 'o Gerente não enxerga OG nem Admin na lista de papéis' do
      get '/api/v1/user_types', headers: auth_headers(gerente)
      names = JSON.parse(response.body)['user_types'].map { |t| t['name'] }
      expect(names).to contain_exactly('gerente', 'colaborador')
    end
  end
end
