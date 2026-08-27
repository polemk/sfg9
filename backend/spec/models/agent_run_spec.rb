# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentRun, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:chat_session).optional }
    it { is_expected.to belong_to(:chat_flow).optional }
  end

  describe 'persistence' do
    it 'grava com todos os campos opcionais em branco' do
      run = described_class.create!
      expect(run).to be_persisted
      expect(run.tools_called).to eq([])
      expect(run.retrieval_chunks).to eq([])
      expect(run.token_usage).to eq({})
      expect(run.loop_count).to eq(0)
    end

    it 'grava payload completo de um turno bem sucedido' do
      run = described_class.create!(
        provider: 'openai',
        model: 'gpt-4o',
        channel: 'waba',
        tools_called: [{ name: 'capture_lead', success: true, duration_ms: 120 }],
        retrieval_chunks: [{ source_label: 'manual.pdf', chunk_index: 3, score: 0.82 }],
        token_usage: { 'prompt' => 1200, 'completion' => 240, 'total' => 1440 },
        latency_ms: 980,
        loop_count: 2,
        status: 'success'
      )
      expect(run.reload.tools_called.first['name']).to eq('capture_lead')
      expect(run.token_usage['total']).to eq(1440)
    end
  end

  describe 'validations' do
    it 'aceita status nil' do
      expect(described_class.new(status: nil)).to be_valid
    end

    it 'aceita status conhecidos' do
      AgentRun::STATUSES.each do |s|
        expect(described_class.new(status: s)).to be_valid
      end
    end

    it 'rejeita status desconhecido' do
      expect(described_class.new(status: 'unknown')).not_to be_valid
    end
  end

  describe 'scopes' do
    let!(:run_ok)   { described_class.create!(status: 'success', provider: 'openai', channel: 'waba', latency_ms: 500) }
    let!(:run_err)  { described_class.create!(status: 'error',   provider: 'openai', channel: 'web',  latency_ms: 3000) }
    let!(:run_slow) { described_class.create!(status: 'success', provider: 'anthropic', channel: 'waba', latency_ms: 8000) }

    it '.failed retorna apenas erros' do
      expect(described_class.failed).to contain_exactly(run_err)
    end

    it '.succeeded retorna apenas sucessos' do
      expect(described_class.succeeded).to contain_exactly(run_ok, run_slow)
    end

    it '.by_provider filtra' do
      expect(described_class.by_provider('anthropic')).to contain_exactly(run_slow)
    end

    it '.by_channel filtra' do
      expect(described_class.by_channel('waba')).to contain_exactly(run_ok, run_slow)
    end

    it '.slower_than(threshold) filtra latência' do
      expect(described_class.slower_than(2000)).to contain_exactly(run_err, run_slow)
    end

    it '.recent ordena desc por created_at' do
      expect(described_class.recent.first).to eq(run_slow)
    end
  end
end
