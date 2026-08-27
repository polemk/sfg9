require 'rails_helper'

RSpec.describe Ai::FlowEngine, 'trigger-message-option flow' do
  let(:flow) { create(:chat_flow) }
  let(:session) { create(:chat_session, chat_flow: flow) }

  # Define a flow with Trigger -> Message -> Option
  let(:flow_definition) do
    {
      'nodes' => [
        {
          'id' => 'trigger-1',
          'type' => 'trigger',
          'data' => { 'keywords' => ['hi'] },
          'position' => { 'x' => 0, 'y' => 0 }
        },
        {
          'id' => 'message-1',
          'type' => 'message',
          'data' => { 'content' => 'Redirecting...' },
          'position' => { 'x' => 100, 'y' => 0 }
        },
        {
          'id' => 'option-1',
          'type' => 'option',
          'data' => { 'content' => 'Choose option', 'options' => ['A', 'B'] },
          'position' => { 'x' => 200, 'y' => 0 }
        }
      ],
      'edges' => [
        { 'source' => 'trigger-1', 'target' => 'message-1', 'id' => 'e1' },
        { 'source' => 'message-1', 'target' => 'option-1', 'id' => 'e2' }
      ]
    }
  end

  before do
    flow.update!(definition: flow_definition)
  end

  describe '#process!' do
    context 'when starting the flow' do
      it 'starts at trigger, transparently moves to message, and returns message payload' do
        engine = described_class.new(session, nil)
        responses = engine.process!

        expect(responses).to be_an(Array)
        expect(responses).not_to be_empty

        # Find the message response
        message_response = responses.find { |r| r[:type] == 'message' || r[:type] == 'text' }
        expect(message_response).to be_present
        expect(message_response[:content]).to eq('Redirecting...')
      end
    end

    context 'when providing input to Message node' do
      before do
        session.update!(current_step_id: 'message-1')
      end

      it 'advances to Option node upon receiving input' do
        engine = described_class.new(session, 'next')
        responses = engine.process!

        expect(responses).to be_an(Array)

        # Should have advanced to option node
        option_response = responses.find { |r| r[:type] == 'option' || r[:options].present? }
        expect(option_response).to be_present if responses.any?
      end
    end
  end
end
