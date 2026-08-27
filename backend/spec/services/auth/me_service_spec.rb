require 'rails_helper'

RSpec.describe Auth::MeService, type: :service do
  let!(:user) { create(:user, name: 'Test User', email: 'test@example.com') }
  let(:service) { described_class.new(user) }

  describe '#show' do
    it 'returns user data' do
      res = service.show
      expect(res[:success]).to be true
      expect(res[:status]).to eq(200)
    end

    it 'returns error if no user' do
      service = described_class.new(nil)
      res = service.show
      expect(res[:success]).to be false
      expect(res[:status]).to eq(401)
    end
  end

  describe '#update' do
    let(:csrf_service) { Auth::CsrfService.new(user) }
    let(:csrf_token) { csrf_service.generate }

    it 'updates user attributes with valid CSRF' do
      res = service.update({ name: 'Updated Name' }, csrf_token)
      expect(res[:success]).to be true
      expect(user.reload.name).to eq('Updated Name')
    end

    it 'returns error for invalid CSRF' do
      res = service.update({ name: 'Updated Name' }, 'invalid_token')
      expect(res[:success]).to be false
      expect(res[:status]).to eq(403)
    end

    it 'returns error for empty params' do
      res = service.update({}, csrf_token)
      expect(res[:success]).to be false
    end
  end
end
