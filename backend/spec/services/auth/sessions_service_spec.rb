require 'rails_helper'

RSpec.describe Auth::SessionsService, type: :service do
  let(:user) { create(:user) }
  let(:token_service) { Auth::TokenService.new(user) }
  let(:tokens) { token_service.generate_tokens }
  let(:access_token) { tokens[:token] }
  let(:refresh_token) { tokens[:refresh_token] }

  describe '.status' do
    it 'returns valid for valid token' do
      res = described_class.status(token: access_token)
      expect(res[:success]).to be true
      expect(res[:data][:valid]).to be true
      user_data = res[:data][:user].as_json
      expect(user_data[:id]).to eq(user.id)
    end

    it 'returns invalid for broken token' do
      res = described_class.status(token: 'broken')
      expect(res[:success]).to be true # Service returns success response with valid: false
      expect(res[:data][:valid]).to be false
    end
  end

  describe '.refresh' do
    it 'refreshes token' do
      res = described_class.refresh(refresh_token: refresh_token)
      expect(res[:success]).to be true
      expect(res[:data].as_json).to have_key(:token)
    end

    it 'fails for invalid refresh token' do
      res = described_class.refresh(refresh_token: 'invalid')
      expect(res[:success]).to be false
    end
  end

  describe '.logout' do
    it 'adds token to denylist' do
      res = described_class.logout(token: access_token)
      expect(res[:success]).to be true
      # Verification of denylist depends on table existence and logic, mostly checking success
    end
  end

  # O /sessions/status decide se a sessão vale. A checagem antiga era
  # `type == 'user' || sub.present?` — e refresh e cable também têm `sub`.
  describe '.status — só o access autentica sessão' do
    it 'recusa um refresh token apresentado como Bearer' do
      res = described_class.status(token: refresh_token)
      expect(res[:data][:valid]).to be false
    end

    it 'recusa um cable token apresentado como Bearer' do
      res = described_class.status(token: token_service.cable_token_for(user.id))
      expect(res[:data][:valid]).to be false
    end

    # Guarda contra "consertar" com lista branca: o access emitido pelo Warden
    # NÃO traz o claim `type`, então exigir type == 'user' derrubaria a sessão real.
    it 'continua aceitando o access token, que não tem claim type' do
      res = described_class.status(token: access_token)
      expect(res[:data][:valid]).to be true
    end
  end

  # Defeito (c): antes só o access ia para a denylist. O refresh sobrevivente
  # reemitia a sessão inteira e o cable seguia abrindo WebSocket até expirar.
  describe '.logout — revoga os TRÊS tokens' do
    it 'grava access, refresh e cable na denylist' do
      cable_token = token_service.cable_token_for(user.id)
      described_class.logout(
        token: access_token, refresh_token: refresh_token, cable_token: cable_token
      )

      [access_token, refresh_token, cable_token].each do |tok|
        payload = JWT.decode(tok, nil, false).first
        expect(Auth::TokenService.revoked?(payload)).to be(true), "token não revogado: #{payload['type'] || 'access'}"
      end
    end
  end
end
