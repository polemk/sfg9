require 'rails_helper'

RSpec.describe WhatsAppWebhookService do
  # Mocks for EvolutionConnection/ActionCable if needed, 
  # or rely on logic that calls them.

  describe '.process_connection_update' do
    let!(:instance) { create(:polemk_instance, instance_id: 'inst_01', connection_status: 'disconnected') }
    
    context 'when payload is valid' do
      let(:payload) { { instanceId: 'inst_01', data: { state: 'open' } } }

      before do
        allow(described_class).to receive(:broadcast_connection_update)
      end

      it 'updates instance status' do
        described_class.process_connection_update(payload)
        expect(instance.reload.connection_status).to eq('connected')
        expect(instance.last_connection_at).to be_present
      end

      it 'broadcasts update' do
        expect(described_class).to receive(:broadcast_connection_update).with(instance, 'open', anything)
        described_class.process_connection_update(payload)
      end
    end

    context 'when instance not found' do
      let(:payload) { { instanceId: 'unknown', data: { state: 'open' } } }
      
      it 'returns error' do
        res = described_class.process_connection_update(payload)
        expect(res[:status]).to eq('error')
        expect(res[:message]).to eq('Instância não encontrada')
      end
    end
  end

  describe '.process_qrcode_updated' do
    let!(:instance) { create(:polemk_instance, instance_id: 'inst_qr') }
    let(:payload) { { instanceId: 'inst_qr', data: { qrcode: { base64: 'qr_base64_string' } } } }

    before do
      allow(described_class).to receive(:broadcast_qrcode_update)
    end

    it 'updates instance qr code' do
      described_class.process_qrcode_updated(payload)
      expect(instance.reload.qr_code).to eq('qr_base64_string')
      expect(instance.connection_status).to_not eq('connected') # Usually stays waiting
    end
  end

  describe '.process_logout_instance' do
    let!(:instance) { create(:polemk_instance, instance_id: 'inst_logout', connection_status: 'connected') }
    let(:payload) { { instanceId: 'inst_logout', data: { reason: 'user request' } } }

    before do
      allow(described_class).to receive(:broadcast_logout_event)
    end

    it 'disconnects instance' do
      described_class.process_logout_instance(payload)
      expect(instance.reload.connection_status).to eq('disconnected')
      expect(instance.logout_reason).to eq('user request')
    end
  end

  describe 'Validation Methods (Private)' do
    # Testing privately to hit coverage lines mostly
    it 'validates connection payload' do
      res = described_class.send(:validate_connection_update_payload, {})
      expect(res[:status]).to eq('error')
    end

    it 'validates qr payload' do
      res = described_class.send(:validate_qrcode_payload, { data: {} })
      expect(res[:status]).to eq('error')
    end
  end
end
