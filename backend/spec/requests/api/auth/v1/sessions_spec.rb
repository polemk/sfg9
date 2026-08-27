require 'rails_helper'

RSpec.describe 'Auth Sessions API', type: :request do
  let(:user) { create(:user) }
  let(:token_service) { Auth::TokenService.new(user) }
  let(:token_data) { token_service.generate_tokens }
  let(:access_token) { token_data[:token] }
  let(:refresh_token) { token_data[:refresh_token] }
  let(:auth_header) { { 'Authorization' => "Bearer #{access_token}" } }

  describe 'GET /auth/v1/sessions/status' do
    it 'returns status with valid token' do
      # Mock SessionsService
      allow(Auth::SessionsService).to receive(:status).and_return({ status: 200, data: { user: user } })
      
      get '/auth/v1/sessions/status', headers: auth_header
      expect(response).to have_http_status(200)
    end
  end

  # O refresh token trafega EXCLUSIVAMENTE em cookie HttpOnly (nunca em body/JSON)
  describe 'POST /auth/v1/sessions/refresh' do
    include ActiveSupport::Testing::TimeHelpers

    it 'refreshes token' do
      allow(Auth::SessionsService).to receive(:refresh).and_return({ status: 200, data: { token: 'new_token' } })

      cookies['refresh_token'] = refresh_token
      post '/auth/v1/sessions/refresh', headers: auth_header
      expect(response).to have_http_status(200).or have_http_status(201)
    end

    # Cenário real de produção: o refresh só é chamado DEPOIS que o access token
    # expirou. Sem mock no SessionsService — o ponto do teste é justamente
    # atravessar o before block do Api::Root, que antes barrava o refresh por
    # causa do Bearer expirado e prendia a sessão ao TTL do access.
    it 'renova a sessão mesmo com o access token expirado no header' do
      tokens = Auth::TokenService.new(user).generate_tokens

      travel_to(1.hour.from_now) do # ACCESS_TTL = 15min; refresh vale 30 dias
        cookies['refresh_token'] = tokens[:refresh_token]
        post '/auth/v1/sessions/refresh',
             headers: { 'Authorization' => "Bearer #{tokens[:token]}" }

        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)).to include('access_token')
      end
    end

    it 'renova a sessão sem nenhum header de Authorization' do
      tokens = Auth::TokenService.new(user).generate_tokens

      cookies['refresh_token'] = tokens[:refresh_token]
      post '/auth/v1/sessions/refresh'

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to include('access_token')
    end

    it 'nunca expõe o refresh token no corpo e rotaciona o cookie HttpOnly' do
      tokens = Auth::TokenService.new(user).generate_tokens

      cookies['refresh_token'] = tokens[:refresh_token]
      post '/auth/v1/sessions/refresh'

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).not_to include('refresh_token')
      set_cookie = response.headers['Set-Cookie'].to_s
      expect(set_cookie).to include('refresh_token=')
      expect(set_cookie.downcase).to include('httponly')
      expect(set_cookie).to include('path=/auth/v1')
    end

    it 'emite o cookie cable_token (HttpOnly, escopo /cable) no refresh' do
      tokens = Auth::TokenService.new(user).generate_tokens

      cookies['refresh_token'] = tokens[:refresh_token]
      post '/auth/v1/sessions/refresh'

      expect(response).to have_http_status(200)
      # cable_token nunca no corpo — só em cookie HttpOnly, fora da URL
      expect(JSON.parse(response.body)).not_to include('cable_token')
      set_cookie = response.headers['Set-Cookie'].to_s
      expect(set_cookie).to include('cable_token=')
      expect(set_cookie).to include('path=/cable')
    end

    # Contraprova: tornar a rota pública não pode ter aberto buraco.
    it 'rejeita refresh token inválido' do
      cookies['refresh_token'] = 'lixo'
      post '/auth/v1/sessions/refresh'

      expect(response).to have_http_status(401)
    end

    it 'rejeita refresh sem cookie' do
      post '/auth/v1/sessions/refresh'

      expect(response).to have_http_status(401)
    end

    it 'rejeita um access token usado como refresh token' do
      tokens = Auth::TokenService.new(user).generate_tokens

      cookies['refresh_token'] = tokens[:token]
      post '/auth/v1/sessions/refresh'

      expect(response).to have_http_status(401)
    end
  end

  describe 'DELETE /auth/v1/sessions/logout' do
    it 'logs out' do
      allow(Auth::SessionsService).to receive(:logout).and_return({ status: 200, message: 'Logout realizado' })

      delete '/auth/v1/sessions/logout', headers: auth_header
      expect(response).to have_http_status(200)
    end
  end
end
