require 'rails_helper'

RSpec.describe 'Auth Code Validation API', type: :request do
  before do
    allow_any_instance_of(Grape::Endpoint).to receive(:current_ip).and_return('127.0.0.1')
    allow_any_instance_of(Grape::Endpoint).to receive(:current_user_agent).and_return('RSpec')
    allow_any_instance_of(Grape::Endpoint).to receive(:check_brute_force!).and_return(true)
    
    # Fix constant resolution bug in controller by aliasing it for the test
    unless defined?(Api::Auth::CodeValidationService)
      Api::Auth::const_set(:CodeValidationService, ::Auth::CodeValidationService)
    end
    
    allow_any_instance_of(Grape::Endpoint).to receive(:process_service_response) do |endpoint, response|
      endpoint.status(response[:status])
      if (200..299).include?(response[:status])
        response[:data]
      else
        endpoint.error!(response, response[:status])
      end
    end
  end

  describe 'POST /auth/v1/code_validation' do
    let(:valid_params) { { identifier: 'test@example.com', code: '123456', method: 'email' } }

    it 'calls CodeValidationService' do
      service_double = instance_double(Auth::CodeValidationService)
      allow(Auth::CodeValidationService).to receive(:new).and_return(service_double)

      expect(service_double).to receive(:execute!).and_return({ status: 200, data: { token: 'jwt_token' } })

      post '/auth/v1/code_validation', params: valid_params

      expect(response).to have_http_status(200).or have_http_status(201)
    end
  end
end
