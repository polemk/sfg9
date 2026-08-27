# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Meta', type: :request do
  describe 'Generic API behavior and Helpers' do
    # Defining a test helper within the context to test the module methods directly
    # or using a dummy endpoint if possible. Since Grape helpers are mixed in,
    # testing via a dummy API mounted in the test is the most robust way.
    
    class TestApi < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      get :success do
        process_service_response({ status: 200, data: { ok: true } })
      end

      get :created do
        process_service_response({ status: 201, data: { ok: true } })
      end

      get :error do
        process_service_response({ status: 400, message: 'Bad request', details: { field: 'invalid' } })
      end

      get :pagination do
        set_pagination_headers(100, 1, 10)
        { data: [] }
      end
      
      get :auth_check do
        authenticate_user!
        { user_id: current_user.id }
      end
    end

    def app
      TestApi
    end

    describe 'helper methods' do
      context '#process_service_response' do
        it 'returns 200 for success' do
          get '/success'
          expect(response.status).to eq(200)
          expect(JSON.parse(response.body)).to eq({ 'ok' => true })
        end

        it 'returns 201 for created' do
          get '/created'
          expect(response.status).to eq(201)
        end

        it 'returns error status and payload' do
          get '/error'
          expect(response.status).to eq(400)
          json = JSON.parse(response.body)
          expect(json['error']).to eq('Bad request')
          expect(json['details']).to eq({ 'field' => 'invalid' })
        end
      end

      context '#set_pagination_headers' do
        it 'sets headers correctly' do
          get '/pagination'
          expect(response.headers['X-Total-Count'].to_s).to eq('100')
          expect(response.headers['X-Page'].to_s).to eq('1')
          expect(response.headers['X-Per-Page'].to_s).to eq('10')
        end
      end
    end
  end
end
