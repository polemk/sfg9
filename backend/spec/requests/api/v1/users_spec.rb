require 'rails_helper'

RSpec.describe 'API V1 Users', type: :request do
  let!(:og_user) { create(:user, :og) }
  let!(:colaborador_user) { create(:user, :colaborador, phone: '5548999999999') }
  let(:og_token) { Auth::TokenService.new(og_user).generate_tokens[:token] }
  let(:colaborador_token) { Auth::TokenService.new(colaborador_user).generate_tokens[:token] }

  before do
    # **DEC-108** — as abilities do legado voltaram e são checadas no servidor.
    # `POST /users`, `DELETE /users/:id`, `/invite` e `POST /memberships` exigem
    # a concessão do papel, que mora no catálogo de referência. Sem semeá-lo,
    # nenhum papel tem nada e todo verbo de escrita daqui viraria 403 — o gate
    # em si tem spec próprio em `abilities_enforcement_spec.rb`.
    Seeds::Reference::Permissions.call!
  end

  describe 'GET /api/v1/users' do
    context 'as OG user' do
      it 'returns users list' do
        get '/api/v1/users', headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json['users']).to be_present
      end

      it 'filters by query' do
        get '/api/v1/users', params: { q: og_user.name }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        ids = JSON.parse(response.body)['users'].map { |u| u['id'] }
        expect(ids).to include(og_user.id)
      end
    end

    context 'as Colaborador user' do
      it 'returns forbidden' do
        get '/api/v1/users', headers: { 'Authorization' => "Bearer #{colaborador_token}" }
        expect(response).to have_http_status(403)
      end
    end

    context 'unauthenticated' do
      it 'returns forbidden/unauthorized' do
        get '/api/v1/users'
        expect(response).to have_http_status(403).or have_http_status(401)
      end
    end
  end

  describe 'GET /api/v1/users/:id' do
    context 'as OG user' do
      it 'returns user details' do
        get "/api/v1/users/#{colaborador_user.id}", headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)['id']).to eq(colaborador_user.id)
      end
    end
  end

  describe 'GET /api/v1/users/find_by_whatsapp' do
    context 'when user exists' do
      it 'returns success' do
        get '/api/v1/users/find_by_whatsapp', params: { whatsapp: colaborador_user.phone }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
      end
    end

    context 'when user does not exist' do
      it 'returns 404' do
        get '/api/v1/users/find_by_whatsapp', params: { whatsapp: '000000000' }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(404)
      end
    end
  end

  describe 'POST /api/v1/users' do
    let(:new_user_params) { { email: 'new@example.com', name: 'New User' } }

    context 'as OG user' do
      it 'creates a user' do
        expect {
          post '/api/v1/users', params: new_user_params, headers: { 'Authorization' => "Bearer #{og_token}" }
        }.to change(User, :count).by(1)
        expect(response).to have_http_status(201)
      end
    end

    context 'as Colaborador user' do
      it 'returns forbidden' do
        post '/api/v1/users', params: new_user_params, headers: { 'Authorization' => "Bearer #{colaborador_token}" }
        expect(response).to have_http_status(403)
      end
    end
  end

  describe 'PUT /api/v1/users/:id' do
    context 'as OG user' do
      it 'updates user' do
        put "/api/v1/users/#{colaborador_user.id}", params: { name: 'Updated Name' }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(colaborador_user.reload.name).to eq('Updated Name')
      end

      it 'updates custom_variables' do
        put "/api/v1/users/#{colaborador_user.id}", params: { custom_variables: { 'score' => '10' } }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(colaborador_user.reload.custom_variables).to eq({ 'score' => '10' })
      end

      it 'updates custom_variables via PATCH' do
        patch "/api/v1/users/#{colaborador_user.id}", params: { custom_variables: { 'interest' => 'coding' } }, headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
        expect(colaborador_user.reload.custom_variables).to eq({ 'interest' => 'coding' })
      end
    end
  end

  describe 'DELETE /api/v1/users/:id' do
    context 'as OG user' do
      it 'deletes user' do
        expect {
          delete "/api/v1/users/#{colaborador_user.id}", headers: { 'Authorization' => "Bearer #{og_token}" }
        }.to change(User, :count).by(-1)
        expect(response).to have_http_status(204)
      end
    end
  end

  describe 'GET /api/v1/users/stats' do
    context 'as OG user' do
      it 'returns stats' do
        get '/api/v1/users/stats', headers: { 'Authorization' => "Bearer #{og_token}" }
        expect(response).to have_http_status(200)
      end
    end
  end
end
