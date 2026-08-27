# frozen_string_literal: true

require 'rails_helper'

# 5.3.3 / 5.3.4 — `user_is_readonly`, a única das 17 abilities do legado que
# sobrevive (DEC-18.6), promovida de flag de view a checagem de servidor.
RSpec.describe 'Gate de somente leitura', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:admin) { create(:user, user_type: UserType.admin) }
  let(:projeto) { create_project_with_owner(admin, slug: 'ro') }
  let(:alvo) { create(:user, user_type: UserType.colaborador) }

  def grant_readonly!(user)
    UserPermission.create!(user: user, permission: Permission.find_by(key: 'user_is_readonly'),
                           source: 'manual', granted_at: Time.current)
  end

  describe 'verbos de escrita' do
    before { projeto }

    it 'NEGA POST/PUT/PATCH/DELETE com 403 e `code` — e PERMITE GET' do
      grant_readonly!(admin)

      post '/api/v1/memberships', params: { user_id: alvo.id }, headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body)['code']).to eq('READONLY_RESTRICTED')

      membership = Membership.create!(project: projeto, user: alvo, role: 'participante')
      delete "/api/v1/memberships/#{membership.id}", headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(403)

      put "/api/v1/users/#{alvo.id}", params: { name: 'X' }, headers: auth_headers(admin)
      expect(response).to have_http_status(403)

      patch "/api/v1/users/#{alvo.id}", params: { name: 'X' }, headers: auth_headers(admin)
      expect(response).to have_http_status(403)

      # O outro lado: a leitura continua funcionando.
      get '/api/v1/memberships', headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(200)
    end

    it 'o MESMO usuário sem a concessão escreve normalmente' do
      post '/api/v1/memberships', params: { user_id: alvo.id }, headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(201)
    end

    it 'revogar a concessão devolve a escrita na requisição SEGUINTE' do
      grant_readonly!(admin)
      post '/api/v1/memberships', params: { user_id: alvo.id }, headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(403)

      UserPermission.where(user: admin).update_all(revoked_at: Time.current)

      post '/api/v1/memberships', params: { user_id: alvo.id }, headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(201)
    end
  end

  # 5.3.4 / DC-09 — sem esta exceção o readonly nunca aceita os Termos e fica
  # trancado fora do sistema.
  describe 'exceção do aceite dos Termos' do
    it 'as rotas de aceite estão na lista de isenção — e uma rota comum não está' do
      exempt = Api::V1::ControllerHelpers::READONLY_EXEMPT_PATHS
      expect(exempt.any? { |r| '/api/v1/contracts/42/accept'.match?(r) }).to be(true)
      expect(exempt.any? { |r| '/api/v1/me/terms'.match?(r) }).to be(true)

      expect(exempt.any? { |r| '/api/v1/memberships'.match?(r) }).to be(false)
      expect(exempt.any? { |r| '/api/v1/users/1'.match?(r) }).to be(false)
    end
  end
end
