require 'rails_helper'

RSpec.describe PolemkWebhookService do
  let!(:instance) { create(:polemk_instance) }

  describe '.create_webhook' do
    it 'configures webhook' do
      expect(EvolutionConnection).to receive(:set_webhook)
      
      result = described_class.create_webhook(url: 'http://example.com')
      expect(result[:status]).to eq('success')
      expect(instance.polemk_webhooks.count).to be > 0
    end
  end

  describe '.test_connection' do
    it 'checks connection' do
      stub_request(:post, "http://example.com/webhook").to_return(status: 200, body: "ok")
      
      result = described_class.test_connection('http://example.com/webhook')
      expect(result[:status]).to eq('success')
    end

    it 'handles errors' do
      stub_request(:post, "http://example.com/webhook").to_timeout
      
      result = described_class.test_connection('http://example.com/webhook')
      expect(result[:status]).to eq(502)
    end
  end
end
