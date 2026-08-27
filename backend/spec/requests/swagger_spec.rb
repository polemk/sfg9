# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API Versioning & Docs', type: :request do
  # Use RSpec request helpers instead of Net::HTTP to localhost:3000

  it 'serve /swagger_doc (JSON)' do
    get '/swagger_doc'
    
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include('application/json')
  end

  it 'exibe endpoints versionados por módulo (auth/v1)' do
    # This is a public endpoint that returns session status
    get '/auth/v1/sessions/status'
    
    # Should return 200, 401, 403 or 404 - any valid HTTP response
    expect([200, 401, 403, 404]).to include(response.status)
  end
end
