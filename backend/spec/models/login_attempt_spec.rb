require 'rails_helper'

RSpec.describe LoginAttempt, type: :model do
  describe 'Associations' do
    it { is_expected.to belong_to(:user).optional }
  end

  describe 'Validations' do
    it { is_expected.to validate_presence_of(:identifier) }
    it { is_expected.to validate_inclusion_of(:method).in_array(%w[email whatsapp google facebook]) }
  end

  describe 'Scopes' do
    let!(:succ) { create(:login_attempt, success: true, created_at: 10.minutes.ago) }
    let!(:fail) { create(:login_attempt, success: false, created_at: 2.hours.ago) }

    it 'filters successful attempts' do
      expect(LoginAttempt.successful).to include(succ)
      expect(LoginAttempt.successful).not_to include(fail)
    end
    
    it 'filters failed attempts' do
      expect(LoginAttempt.failed).to include(fail)
      expect(LoginAttempt.failed).not_to include(succ)
    end

    it 'filters by time' do
      expect(LoginAttempt.last_hour).to include(succ)
      expect(LoginAttempt.last_hour).not_to include(fail)
    end
  end

  describe '.log_attempt!' do
    it 'creates normalized attempt' do
      attempt = LoginAttempt.log_attempt!('  Test@Example.com ', 'email', '1.2.3.4', 'TestAgent', true)
      expect(attempt.identifier).to eq('test@example.com')
      expect(attempt.success).to be true
    end

    it 'normalizes whatsapp' do
      attempt = LoginAttempt.log_attempt!('(11) 99999-9999', 'whatsapp', '1.2.3.4', 'TestAgent', false)
      expect(attempt.identifier).to eq('11999999999')
    end
  end

  describe 'Security Checks' do
    before { LoginAttempt.destroy_all }
    
    describe '.suspicious_activity?' do
      it 'detects multiple identifier failures' do
        5.times { create(:login_attempt, identifier: 'hacker', success: false) }
        expect(LoginAttempt.suspicious_activity?('hacker')).to be true
      end

      it 'returns false for few failures' do
        4.times { create(:login_attempt, identifier: 'safe', success: false) }
        expect(LoginAttempt.suspicious_activity?('safe')).to be false
      end
      
      it 'detects dangerous IP' do
        10.times { create(:login_attempt, ip_address: '6.6.6.6', success: false) }
        expect(LoginAttempt.suspicious_activity?('any', '6.6.6.6')).to be true
      end
    end

    describe '.brute_force_detected?' do
      it 'detects rapid attempts' do
        attempts = []
        5.times do |i|
          attempts << create(:login_attempt, identifier: 'victim', created_at: Time.current + i.seconds)
        end
        expect(LoginAttempt.brute_force_detected?('victim')).to be true
      end
    end
  end

  describe 'Statistics' do
    before do
       LoginAttempt.destroy_all
       create_list(:login_attempt, 8, success: true)
       create_list(:login_attempt, 2, success: false)
    end

    it 'calculates success rate' do
      expect(LoginAttempt.login_success_rate).to eq(80.0)
    end
  end

  describe '#user_agent_info' do
    it 'parses Chrome/Windows' do
      ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      attempt = build(:login_attempt, user_agent: ua)
      info = attempt.user_agent_info
      expect(info[:browser]).to eq('Chrome')
      expect(info[:os]).to eq('Windows')
      expect(info[:device]).to eq('Desktop')
    end

    it 'parses iPhone' do
      ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Mobile/15E148 Safari/604.1'
      attempt = build(:login_attempt, user_agent: ua)
      info = attempt.user_agent_info
      expect(info[:os]).to eq('iOS')
      expect(info[:device]).to eq('Mobile')
    end
  end
end
