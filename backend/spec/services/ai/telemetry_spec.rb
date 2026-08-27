# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Telemetry do
  describe '.record' do
    it 'persiste um AgentRun e retorna o registro' do
      run = described_class.record(provider: 'openai', model: 'gpt-4o', channel: 'web', status: 'success', latency_ms: 100)

      expect(run).to be_a(AgentRun).and(be_persisted)
      expect(run.provider).to eq('openai')
    end

    it 'emite log estruturado com prefixo [AgentRun]' do
      expect(Rails.logger).to receive(:info).with(/\[AgentRun\] turn .*provider=openai.*latency_ms=120/)

      described_class.record(provider: 'openai', model: 'gpt-4o', channel: 'waba', status: 'success', latency_ms: 120)
    end

    it 'retorna nil e não propaga erro quando a persistência falha' do
      allow(AgentRun).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'simulated')

      expect { described_class.record(provider: 'openai') }.not_to raise_error
      expect(described_class.record(provider: 'openai')).to be_nil
    end

    it 'loga warning quando persistência falha (com classe de erro)' do
      allow(AgentRun).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'simulated')
      expect(Rails.logger).to receive(:warn).with(/\[AgentRun\] persistência ignorada: ActiveRecord::StatementInvalid/)

      described_class.record(provider: 'openai')
    end
  end

  describe '.log' do
    it 'emite mensagem com prefixo [AgentRun]' do
      expect(Rails.logger).to receive(:info).with('[AgentRun] hello world')
      described_class.log(:info, 'hello world')
    end

    it 'serializa payload em key=value' do
      expect(Rails.logger).to receive(:warn).with('[AgentRun] something bad foo=1 bar=baz')
      described_class.log(:warn, 'something bad', { foo: 1, bar: 'baz' })
    end

    it 'envolve strings com espaço em aspas' do
      expect(Rails.logger).to receive(:info).with(%([AgentRun] msg name="John Doe"))
      described_class.log(:info, 'msg', { name: 'John Doe' })
    end

    it 'nunca propaga erro de logging' do
      allow(Rails.logger).to receive(:info).and_raise(IOError, 'disk full')
      expect { described_class.log(:info, 'hi') }.not_to raise_error
    end
  end
end
