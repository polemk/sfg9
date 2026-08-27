require 'rails_helper'

RSpec.describe "Api::V1::Credentials", type: :request do
  let(:base_url) { '/api/v1/credentials' }
  let(:user) { create(:user, :og) }
  let(:headers) { { 'Authorization' => "Bearer test_token" } }

  include Warden::Test::Helpers

  before do
    login_as(user, scope: :user)
    allow_any_instance_of(Grape::Endpoint).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Grape::Endpoint).to receive(:current_user).and_return(user)
    allow_any_instance_of(Grape::Endpoint).to receive(:require_og!).and_return(true)
    allow_any_instance_of(Api::V1::Credentials).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Api::V1::Credentials).to receive(:current_user).and_return(user)
    allow_any_instance_of(Api::V1::Credentials).to receive(:require_og!).and_return(true)
  end

  describe "GET /api/v1/credentials" do
    let!(:credential) { Credential.create!(name: 'Test Key 1', provider: 'openai', api_key: 'sk-proj-super-secret-1') }
    let!(:credential2) { Credential.create!(name: 'Test Key 2', provider: 'anthropic', api_key: 'sk-ant-api03-secret-2') }

    it "returns all credentials with masked api keys" do
      get base_url, headers: headers
      
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      
      expect(body.size).to eq(2)
      
      # Ensure real api key is never sent
      body.each do |c|
        expect(c).not_to have_key('api_key')
        expect(c).not_to have_key('api_key_ciphertext')
        expect(c).to have_key('id')
        expect(c).to have_key('name')
        expect(c).to have_key('provider')
        expect(c).to have_key('api_key_masked')
      end

      expect(body[0]['api_key_masked']).to eq("sk-a...et-2") # order is desc created_at
      expect(body[1]['api_key_masked']).to eq("sk-p...et-1")
    end
  end

  describe "POST /api/v1/credentials" do
    let(:valid_params) {
      {
        name: 'New OpenAI Key',
        provider: 'openai',
        api_key: 'sk-proj-abcdef123456'
      }
    }

    it "creates a new credential and returns it masked" do
      post base_url, params: valid_params, headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)

      expect(body['name']).to eq('New OpenAI Key')
      expect(body['provider']).to eq('openai')
      expect(body['api_key_masked']).to eq('sk-p...3456')
      expect(body['api_key']).to be_nil

      # Verify it's in the DB encrypted
      expect(Credential.count).to eq(1)
      cred = Credential.last
      expect(cred.api_key).to eq('sk-proj-abcdef123456')
    end
  end

  describe "DELETE /api/v1/credentials/:id" do
    let!(:credential) { Credential.create!(name: 'To Be Deleted', provider: 'google', api_key: 'gcp-secret') }

    it "deletes the credential" do
      delete "#{base_url}/#{credential.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(Credential.exists?(credential.id)).to be_falsey
    end
  end
end
