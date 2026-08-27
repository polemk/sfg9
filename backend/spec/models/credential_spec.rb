require 'rails_helper'

RSpec.describe Credential, type: :model do
  describe 'validations' do
    subject { Credential.new(name: 'Valid Name', provider: 'openai', api_key: 'secret') }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_presence_of(:provider) }
    it { should validate_inclusion_of(:provider).in_array(%w[openai anthropic google]) }
    it { should validate_presence_of(:api_key) }
  end

  describe '#masked_api_key' do
    it 'returns nil if api_key is blank' do
      credential = Credential.new(api_key: nil)
      expect(credential.masked_api_key).to be_nil
    end

    it 'masks a long api key correctly' do
      credential = Credential.new(api_key: 'sk-proj-somethingverysecret1234')
      expect(credential.masked_api_key).to eq('sk-p...1234')
    end

    it 'masks a short api key correctly' do
      credential = Credential.new(api_key: 'short')
      expect(credential.masked_api_key).to eq('sh...rt')
    end
  end

  describe 'encryption' do
    it 'encrypts the api_key column' do
      credential = Credential.create!(
        name: 'Test Key',
        provider: 'openai',
        api_key: 'super_secret_key'
      )

      # Reloading from DB should decrypt transparently
      credential.reload
      expect(credential.api_key).to eq('super_secret_key')

      # Check raw DB value to ensure it's not plaintext
      raw_db_value = ActiveRecord::Base.connection.execute(
        "SELECT api_key FROM credentials WHERE id = #{credential.id}"
      ).first['api_key']

      expect(raw_db_value).not_to include('super_secret_key')
      expect(raw_db_value).to be_present
    end
  end
end
