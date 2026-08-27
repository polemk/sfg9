# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::ControllerHelpers, type: :request do
  # Mock class to include the module
  class DummyController
    include Api::V1::ControllerHelpers
    attr_accessor :response_headers, :env

    def initialize
      @response_headers = {}
      @env = {}
    end

    def status(code)
      @status = code
    end

    def header(key, value)
      @response_headers[key] = value
    end

    def error!(payload, code)
      raise StandardError, "Error #{code}: #{payload}"
    end
  end

  let(:controller) { DummyController.new }

  describe '#process_service_response' do
    context 'when status is success (200-299)' do
      it 'returns the data' do
        response = { status: 200, data: { id: 1 } }
        expect(controller.process_service_response(response)).to eq({ id: 1 })
      end

      it 'sets the status' do
        response = { status: 201, data: { id: 1 } }
        controller.process_service_response(response)
        expect(controller.instance_variable_get(:@status)).to eq(201)
      end
    end

    context 'when status is error (400+)' do
      it 'raises error with correct payload' do
        response = { status: 400, error: 'bad_request', message: 'Invalid params' }
        expect {
          controller.process_service_response(response)
        }.to raise_error(StandardError, /Error 400/)
      end

      it 'includes details if present' do
        response = { status: 422, error: 'validation_error', details: { field: ['error'] } }
        expect {
          controller.process_service_response(response)
        }.to raise_error(StandardError, /details/)
      end
    end
  end

  # DEC-62 — o envelope de paginação vai em CABEÇALHO, decidido uma vez para
  # todos os endpoints. `X-Total-Pages` existe porque é o que o `PaginationPill`
  # espera; derivar no cliente é onde os dois lados divergem.
  describe '#set_pagination_headers' do
    it 'emite os 4 cabeçalhos do envelope' do
      controller.set_pagination_headers(100, 1, 10)
      headers = controller.instance_variable_get(:@response_headers)
      expect(headers['X-Total-Count']).to eq('100')
      expect(headers['X-Page']).to eq('1')
      expect(headers['X-Per-Page']).to eq('10')
      expect(headers['X-Total-Pages']).to eq('10')
    end

    it 'arredonda a última página para cima' do
      controller.set_pagination_headers(101, 1, 10)
      expect(controller.instance_variable_get(:@response_headers)['X-Total-Pages']).to eq('11')
    end

    it 'trata total zero sem divisão por zero' do
      controller.set_pagination_headers(0, 1, 10)
      expect(controller.instance_variable_get(:@response_headers)['X-Total-Pages']).to eq('0')
    end
  end

  describe '#authenticate_user!' do
    it 'sets @current_user if authenticated' do
      user = double('User')
      controller.env['api.current_user'] = user
      controller.authenticate_user!
      expect(controller.instance_variable_get(:@current_user)).to eq(user)
    end

    it 'raises 401 if not authenticated' do
      controller.env['api.current_user'] = nil
      expect {
        controller.authenticate_user!
      }.to raise_error(StandardError, /Error 401/)
    end
  end
end
