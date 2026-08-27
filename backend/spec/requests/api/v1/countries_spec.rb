require 'rails_helper'

RSpec.describe 'API V1 Countries', type: :request do
  let!(:og_user) { create(:user, :og) }
  let(:token) { Auth::TokenService.new(og_user).generate_tokens[:token] }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  describe 'GET /api/v1/countries' do
    it 'returns countries list' do
      get '/api/v1/countries', headers: headers
      expect(response).to have_http_status(200)
    end
  end
end
