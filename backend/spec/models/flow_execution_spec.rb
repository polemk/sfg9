require 'rails_helper'

RSpec.describe FlowExecution, type: :model do
  let(:flow) { create(:chat_flow) }
  let(:session) { create(:chat_session, chat_flow: flow) }

  describe 'validations' do
    it 'requires node_id' do
      execution = FlowExecution.new(
        chat_session: session,
        chat_flow: flow,
        node_type: 'text'
      )
      expect(execution).not_to be_valid
      expect(execution.errors[:node_id]).to be_present
    end

    it 'requires node_type' do
      execution = FlowExecution.new(
        chat_session: session,
        chat_flow: flow,
        node_id: 'node-1'
      )
      expect(execution).not_to be_valid
      expect(execution.errors[:node_type]).to be_present
    end

    it 'is valid with required attributes' do
      execution = FlowExecution.new(
        chat_session: session,
        chat_flow: flow,
        node_id: 'node-1',
        node_type: 'text'
      )
      expect(execution).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:chat_session) }
    it { is_expected.to belong_to(:chat_flow) }
  end

  describe 'scopes' do
    let!(:exec1) { create(:flow_execution, chat_session: session, chat_flow: flow, node_type: 'trigger', created_at: 2.minutes.ago) }
    let!(:exec2) { create(:flow_execution, chat_session: session, chat_flow: flow, node_type: 'text', created_at: 1.minute.ago) }

    describe '.ordered' do
      it 'returns executions in chronological order' do
        expect(FlowExecution.ordered).to eq([exec1, exec2])
      end
    end

    describe '.recent' do
      it 'returns executions in reverse chronological order' do
        expect(FlowExecution.recent).to eq([exec2, exec1])
      end
    end

    describe '.by_type' do
      it 'filters by node_type' do
        expect(FlowExecution.by_type('trigger')).to eq([exec1])
        expect(FlowExecution.by_type('text')).to eq([exec2])
      end
    end
  end

  describe '#summary' do
    it 'returns appropriate summary for trigger type' do
      exec = build(:flow_execution, node_type: 'trigger')
      expect(exec.summary).to eq('Iniciou fluxo')
    end

    it 'returns appropriate summary for text type' do
      exec = build(:flow_execution, node_type: 'text', output_data: { 'content' => 'Hello World' })
      expect(exec.summary).to include('Mensagem:')
    end

    it 'returns appropriate summary for question type' do
      exec = build(:flow_execution, node_type: 'question', input_data: { 'user_input' => 'John' })
      expect(exec.summary).to include('Pergunta respondida:')
    end

    it 'returns appropriate summary for redirect type' do
      exec = build(:flow_execution, node_type: 'redirect', output_data: { 'action' => 'scroll_to' })
      expect(exec.summary).to include('Ação:')
    end
  end
end
