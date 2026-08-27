require 'rails_helper'

RSpec.describe Auth::CsrfService, type: :service do
  let!(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe '#generate' do
    it 'generates a CSRF token' do
      token = service.generate
      expect(token).to be_present
      expect(token.length).to be > 10
    end
  end

  describe '#valid?' do
    it 'validates correct token' do
      token = service.generate
      expect(service.valid?(token)).to be true
    end

    it 'rejects invalid token' do
      service.generate
      expect(service.valid?('invalid_token')).to be false
    end
  end
end
