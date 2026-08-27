require 'rails_helper'

RSpec.describe LoginCode, type: :model do
  describe 'Validations' do
    subject { build(:login_code) }

    subject { build(:login_code) }

    it { is_expected.to validate_presence_of(:destination) }
  end

  describe 'Callbacks' do
    it 'generates code and expiration on create' do
      code = LoginCode.create(destination: 'test@example.com', method: 'email')
      expect(code.code).to be_present
      expect(code.expires_at).to be_present
      expect(code.expires_at).to be > Time.current
    end
  end

  describe 'Instance Methods' do
    let(:code) { create(:login_code) }

    it '#expired? returns true if past expiration' do
      code.expires_at = 1.minute.ago
      expect(code).to be_expired
    end

    it '#expired? returns false if future' do
      code.expires_at = 1.minute.from_now
      expect(code).not_to be_expired
    end

    describe '#valid_code?' do
      it 'returns true when valid' do
        expect(code.valid_code?).to be true
      end

      it 'returns false if expired' do
        code.expires_at = 1.minute.ago
        expect(code.valid_code?).to be false
      end

      it 'returns false if used' do
        code.used_at = Time.current
        expect(code.valid_code?).to be false
      end
    end

    describe '#matches?' do
      it 'returns true for matching code' do
        expect(code.matches?(code.code)).to be true
      end

      it 'returns false for mismatch' do
        expect(code.matches?('wrong')).to be false
      end
    end

    it '#use! sets used_at' do
      expect {
        code.use!
      }.to change { code.reload.used_at }.from(nil)
    end
  end
end
