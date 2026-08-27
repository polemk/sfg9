require 'rails_helper'

RSpec.describe 'Api::V1::Downloads', type: :request do
  let(:user) { create(:user) }
  let(:token) { Auth::TokenService.new(user).generate_tokens[:token] }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  describe 'GET /api/v1/downloads/basic' do
    context 'when user has basic permission' do
      before do
        permission = create(:permission, :download_basic)
        create(:user_permission, user: user, permission: permission)
        # Mock file existence
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:binread).and_return('CONTENT')
      end

      it 'returns the basic build file' do
        get '/api/v1/downloads/basic', headers: headers
        puts "Response: #{response.status} - #{response.body}" if response.status != 200
        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to include('ai9_build_basic.zip')
      end
    end

    context 'when user does not have permission' do
      it 'returns 403' do
        get '/api/v1/downloads/basic', headers: headers
        puts "Response: #{response.status} - #{response.body}" if response.status != 403
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/downloads/full' do
    context 'when user has full permission' do
      before do
        permission = create(:permission, :download_full)
        create(:user_permission, user: user, permission: permission)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:binread).and_return('CONTENT')
      end

      it 'returns the full build file' do
        get '/api/v1/downloads/full', headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to include('ai9_build_full.zip')
      end
    end
    
    context 'when user has only basic permission' do
      before do
        permission = create(:permission, :download_basic)
        create(:user_permission, user: user, permission: permission)
      end

      it 'returns 403 on full download' do
        get '/api/v1/downloads/full', headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
