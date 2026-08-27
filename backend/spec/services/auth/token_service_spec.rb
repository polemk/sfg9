require 'rails_helper'

RSpec.describe Auth::TokenService, type: :service do
  let!(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe '#generate_tokens' do
    it 'generates access and refresh tokens' do
      tokens = service.generate_tokens
      expect(tokens[:token]).to be_present
      expect(tokens[:refresh_token]).to be_present
    end

    it 'returns different tokens for access and refresh' do
      tokens = service.generate_tokens
      expect(tokens[:token]).not_to eq(tokens[:refresh_token])
    end
  end

  describe '#decode_token' do
    it 'decodes a valid access token' do
      tokens = service.generate_tokens
      payload = service.decode_token(tokens[:token])
      expect(payload['sub']).to eq(user.id)
    end

    it 'decodes a valid refresh token' do
      tokens = service.generate_tokens
      payload = service.decode_token(tokens[:refresh_token])
      expect(payload['sub']).to eq(user.id)
      expect(payload['type']).to eq('refresh')
    end

    it 'raises error for invalid token' do
      expect {
        service.decode_token('invalid_token')
      }.to raise_error(JWT::DecodeError)
    end
  end
end
