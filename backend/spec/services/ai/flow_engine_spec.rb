require 'rails_helper'

RSpec.describe Ai::FlowEngine do
  let(:flow) { create(:chat_flow, :onboarding) }
  let(:session) { create(:chat_session, chat_flow: flow) }

  describe '#process!' do
    context 'when starting a new session' do
      it 'returns an array of responses with the start node payload' do
        engine = described_class.new(session)
        responses = engine.process!

        expect(responses).to be_an(Array)
        expect(responses).not_to be_empty

        # Find the text/message response
        text_response = responses.find { |r| r[:type] == 'text' || r[:type] == 'message' }
        expect(text_response).to be_present
        expect(text_response[:content]).to eq('Hello! Welcome.')
      end
    end

    context 'when processing input' do
      before do
        session.update!(current_step_id: 'ask_name')
      end

      it 'advances to next node on valid input' do
        engine = described_class.new(session, 'John Doe')
        responses = engine.process!

        expect(responses).to be_an(Array)
        expect(session.reload.context['name']).to eq('John Doe')

        # Find the response with content containing the name
        content_response = responses.find { |r| r[:content]&.include?('John Doe') }
        expect(content_response).to be_present if responses.any? { |r| r[:content].present? }
      end
    end

    context 'when logging executions' do
      it 'creates FlowExecution records for each step' do
        engine = described_class.new(session)

        expect {
          engine.process!
        }.to change(FlowExecution, :count).by_at_least(1)
      end

      it 'does not log executions for test sessions' do
        session.update!(context: { 'is_test' => true })
        engine = described_class.new(session)

        expect {
          engine.process!
        }.not_to change(FlowExecution, :count)
      end
    end
    context 'when processing handoff node' do
      let(:target_flow) { create(:chat_flow, name: 'Target Flow', definition: { 'nodes' => [{ 'id' => 'start2', 'type' => 'text', 'content' => 'Welcome to target flow' }], 'edges' => [] }) }

      it 'transitions to the target flow and returns its initial responses' do
        session.chat_flow.update!(definition: {
          'nodes' => [
            { 'id' => 'start', 'type' => 'handoff', 'data' => { 'target_flow_id' => target_flow.id } }
          ],
          'edges' => []
        })
        session.update!(current_step_id: 'start')

        engine = described_class.new(session)
        responses = engine.process!

        expect(session.reload.chat_flow_id).to eq(target_flow.id)
        
        # We expect a handoff response from the current flow AND the welcome from the new flow
        handoff_response = responses.find { |r| r[:action] == 'handoff' }
        expect(handoff_response).to be_present
        expect(handoff_response[:target_flow_id]).to eq(target_flow.id)

        text_response = responses.find { |r| r[:content] == 'Welcome to target flow' }
        expect(text_response).to be_present
      end

      it 'prevents infinite loops across multiple handoffs' do
        # Flow A (session.chat_flow) -> Flow B -> Flow A
        flow_b = create(:chat_flow, name: 'Flow B', definition: {
          'nodes' => [
            { 'id' => 'b_start', 'type' => 'handoff', 'data' => { 'target_flow_id' => session.chat_flow.id } }
          ],
          'edges' => []
        })
        
        session.chat_flow.update!(definition: {
          'nodes' => [
             { 'id' => 'a_start', 'type' => 'handoff', 'data' => { 'target_flow_id' => flow_b.id } }
          ],
          'edges' => []
        })
        session.update!(current_step_id: 'a_start')

        engine = described_class.new(session)
        responses = engine.process!

        # Should halt safely after hitting the limit
        error_response = responses.find { |r| r[:type] == 'end' }
        expect(error_response).to be_present
        expect(error_response[:content]).to match(/Loop/i)
      end
    end
  end
end
