require 'rails_helper'

RSpec.describe 'API V1 Permissions', type: :request do
  let!(:og_user) { create(:user, :og) }
  let(:token) { Auth::TokenService.new(og_user).generate_tokens[:token] }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }
  let!(:permission) { create(:permission) }
  let!(:user_permission) { create(:user_permission, user: og_user, permission: permission) }

  describe 'GET /api/v1/permissions/me' do
    it 'returns current user permissions' do
      get '/api/v1/permissions/me', headers: headers
      expect(response).to have_http_status(200)
    end
  end

  # POST /api/v1/permissions/sync saiu no Bloco 4 junto com o AI9-002: a
  # sincronizacao existia so para propagar plan_features -> permissions.
  describe 'POST /api/v1/permissions/sync' do
    it 'nao existe mais' do
      post '/api/v1/permissions/sync', params: { user_id: og_user.id }, headers: headers
      expect(response).to have_http_status(404)
    end
  end
end
