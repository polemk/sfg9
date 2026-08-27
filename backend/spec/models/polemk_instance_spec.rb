# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PolemkInstance, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:polemk_webhooks).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:display_name) }
    it { is_expected.to validate_presence_of(:instance_name) }
    
    # Needs a subject for uniqueness validation
    subject { build(:polemk_instance) }
    before do
      # Factory extracted to spec/factories/polemk_instances.rb
    end

    it { is_expected.to validate_presence_of(:instance_id) }
    it { is_expected.to validate_uniqueness_of(:instance_id) }
    it { is_expected.to validate_presence_of(:api_key) }
    it { is_expected.to validate_inclusion_of(:connection_status).in_array(PolemkInstance::CONNECTION_STATUSES) }
  end

  describe 'scopes' do
    let!(:connected) { create(:polemk_instance, connection_status: 'connected') }
    let!(:disconnected) { create(:polemk_instance, connection_status: 'disconnected') }
    let!(:waiting) { create(:polemk_instance, connection_status: 'waiting_qr') }

    describe '.connected' do
      it 'returns only connected instances' do
        expect(described_class.connected).to include(connected)
        expect(described_class.connected).not_to include(disconnected, waiting)
      end
    end

    describe '.disconnected' do
      it 'returns only disconnected instances' do
        expect(described_class.disconnected).to include(disconnected)
        expect(described_class.disconnected).not_to include(connected, waiting)
      end
    end

    describe '.waiting_qr' do
      it 'returns only instances waiting for QR' do
        expect(described_class.waiting_qr).to include(waiting)
        expect(described_class.waiting_qr).not_to include(connected, disconnected)
      end
    end
  end

  describe 'methods' do
    let(:instance) { build(:polemk_instance, connection_status: 'connected') }

    describe '#connected?' do
      it 'returns true if status is connected' do
        expect(instance).to be_connected
      end

      it 'returns false otherwise' do
        instance.connection_status = 'disconnected'
        expect(instance).not_to be_connected
      end
    end

    describe '.normalize_instance_name' do
      it 'normalizes the display name' do
        expect(described_class.normalize_instance_name('My Instance')).to eq('MY_INSTANCE')
      end

      it 'handles nil' do
        expect(described_class.normalize_instance_name(nil)).to be_nil
      end
    end
  end
end
