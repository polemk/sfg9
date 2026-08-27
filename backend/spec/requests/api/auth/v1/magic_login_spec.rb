require 'rails_helper'

RSpec.describe 'Auth Magic Login API', type: :request do
  before do
    # Stub helpers globally on Grape::Endpoint since direct helper injection didn't work
    allow_any_instance_of(Grape::Endpoint).to receive(:current_ip).and_return('127.0.0.1')
    allow_any_instance_of(Grape::Endpoint).to receive(:current_user_agent).and_return('RSpec')
    allow_any_instance_of(Grape::Endpoint).to receive(:check_brute_force!).and_return(true)
    allow_any_instance_of(Grape::Endpoint).to receive(:check_rate_limit!).and_return(true)
    
    allow_any_instance_of(Grape::Endpoint).to receive(:process_service_response) do |endpoint, response|
      endpoint.status(response[:status])
      if (200..299).include?(response[:status])
        response[:data]
      else
        endpoint.error!(response, response[:status])
      end
    end
  end

  describe 'POST /auth/v1/magic_login/request_code' do
    let(:valid_params) { { identifier: 'test@example.com', method: 'email' } }

    context 'with valid parameters' do
      it 'calls MagicLoginService and returns success' do
        service_double = instance_double(Auth::MagicLoginService)
        allow(Auth::MagicLoginService).to receive(:new).and_return(service_double)
        
        expect(service_double).to receive(:execute!).and_return({ status: 200, data: { success: true } })

        post '/auth/v1/magic_login/request_code', params: valid_params

        expect(response).to have_http_status(200).or have_http_status(201)
      end
    end
  end

  describe 'POST /auth/v1/magic_login/validate_code' do
    let(:valid_params) { { identifier: 'test@example.com', code: '123456', method: 'email' } }

    it 'calls CodeValidationService and returns token' do
      service_double = instance_double(Auth::CodeValidationService)
      allow(Auth::CodeValidationService).to receive(:new).and_return(service_double)

      expect(service_double).to receive(:execute!).and_return({ status: 200, data: { token: 'jwt_token' } })

      post '/auth/v1/magic_login/validate_code', params: valid_params

      expect(response).to have_http_status(200).or have_http_status(201)
      json = JSON.parse(response.body)
      expect(json['token']).to eq('jwt_token')
    end
  end

  describe 'POST /auth/v1/magic_login/can_resend' do
    let(:valid_params) { { identifier: 'test@example.com', method: 'email' } }
    
    it 'checks LoginCode' do
      create(:login_code, destination: 'test@example.com', method: 'email', created_at: Time.current)
      
      post '/auth/v1/magic_login/can_resend', params: valid_params
      
      expect(response).to have_http_status(200).or have_http_status(201)
      json = JSON.parse(response.body)
      expect(json['can_resend']).to be false
    end
  end
end
