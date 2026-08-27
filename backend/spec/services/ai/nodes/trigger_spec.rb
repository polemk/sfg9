
require 'rails_helper'

RSpec.describe Ai::Nodes::Trigger do
  let(:session) { instance_double(ChatSession) }
  let(:step_with_content) { { 'id' => '1', 'type' => 'trigger', 'content' => 'Welcome', 'data' => { 'content' => 'Welcome' } } }
  let(:step_without_content) { { 'id' => '2', 'type' => 'trigger', 'data' => {} } }

  describe '#transparent?' do
    it 'returns true if content is missing' do
      node = described_class.new(step_without_content, session)
      expect(node.transparent?).to be true
    end

    it 'returns false if content is present' do
      node = described_class.new(step_with_content, session)
      expect(node.transparent?).to be false
    end
  end

  describe '#payload' do
    it 'includes content in payload' do
      node = described_class.new(step_with_content, session)
      expect(node.payload[:content]).to eq('Welcome')
    end
  end
end
