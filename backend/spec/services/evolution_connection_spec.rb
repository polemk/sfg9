require 'rails_helper'

RSpec.describe EvolutionConnection do
  describe '.instance_name' do
    context 'when instance exists' do
      let!(:instance) { create(:polemk_instance, instance_name: 'test_instance') }
      
      it 'returns the instance name' do
        expect(described_class.instance_name).to eq('test_instance')
      end
    end

    context 'when no instance exists' do
      before do
        PolemkInstance.delete_all
        described_class.instance_variable_set(:@instance, nil)
      end
      
      it 'returns nil' do
        expect(described_class.instance_name).to be_nil
      end
    end
  end

  # Add more tests for other methods...
end
