
require 'rails_helper'

RSpec.describe Ai::Nodes::BaseNode do
  let(:step_data) do
    {
      'id' => 'node_1',
      'type' => 'text',
      'content' => 'Hello',
      'data' => {
        'blocks' => [
          { 'type' => 'text', 'content' => 'Hello' },
          { 'type' => 'delay', 'seconds' => 3 }
        ]
      }
    }
  end

  let(:session) { instance_double(ChatSession) }

  subject { described_class.new(step_data, session, nil) }

  describe '#payload' do
    it 'includes blocks in the payload' do
      expect(subject.payload[:blocks]).to eq([
        { 'type' => 'text', 'content' => 'Hello' },
        { 'type' => 'delay', 'seconds' => 3 }
      ])
    end
  end
end
