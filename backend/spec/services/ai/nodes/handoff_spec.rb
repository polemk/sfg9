require 'rails_helper'

RSpec.describe Ai::Nodes::Handoff do
  let(:source_flow) { create(:chat_flow, name: 'Source Flow') }
  let(:target_flow) { create(:chat_flow, name: 'Target Flow') }
  let(:session) { create(:chat_session, chat_flow: source_flow) }
  
  let(:step_data) do
    {
      'id' => 'handoff_node_1',
      'type' => 'handoff',
      'data' => {
        'target_flow_id' => target_flow.id
      }
    }
  end

  subject(:node) { described_class.new(step_data, session) }

  describe '#target_flow_id' do
    it 'returns the target flow id from data' do
      expect(node.target_flow_id).to eq(target_flow.id)
    end
  end

  describe '#process!' do
    it 'does nothing (logic handled by engine)' do
      expect { node.process! }.not_to raise_error
    end
  end

  describe '#transparent?' do
    it 'returns false' do
      expect(node.transparent?).to be(false)
    end
  end
end
