# frozen_string_literal: true

require 'rails_helper'

# Bloco 8 do trim (AI9-007) — DEC-20: o histórico do assistente vive em
# memória/Redis, sem tabela nova.
#
# `config/environments/test.rb` usa `:null_store` (escrita é no-op, leitura devolve
# nil), então cada exemplo troca o store por um `MemoryStore` de verdade — senão o
# spec provaria só que o null_store não guarda nada.
RSpec.describe Ai::ConversationMemory do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:user) { create(:user) }
  let(:flow) { create(:chat_flow) }
  let(:session) { create(:chat_session, chat_flow: flow, user: user) }

  before { allow(Rails).to receive(:cache).and_return(store) }

  describe '.key_for' do
    it 'inclui o USUÁRIO, não só a sessão' do
      expect(described_class.key_for(session)).to eq(
        "#{described_class::KEY_PREFIX}:u#{user.id}:s#{session.id}"
      )
    end

    it 'devolve nil para sessão sem dono — órfã não compartilha chave com ninguém' do
      orfa = create(:chat_session, chat_flow: flow)
      expect(described_class.key_for(orfa)).to be_nil
    end
  end

  describe '.append / .history_for' do
    it 'começa vazio' do
      expect(described_class.history_for(session)).to eq([])
    end

    it 'guarda o turno e devolve no formato que os providers consomem' do
      described_class.append(session, user_content: 'meu nome é Vinícius',
                                      assistant_content: 'prazer, Vinícius')

      expect(described_class.history_for(session)).to eq([
        { role: 'user',      content: 'meu nome é Vinícius' },
        { role: 'assistant', content: 'prazer, Vinícius' }
      ])
    end

    it 'acumula turnos na ordem' do
      described_class.append(session, user_content: 'a', assistant_content: 'A')
      described_class.append(session, user_content: 'b', assistant_content: 'B')

      expect(described_class.history_for(session).map { |m| m[:content] }).to eq(%w[a A b B])
    end

    it 'corta pelo fim no MAX_MESSAGES — janela de contexto, não retenção' do
      (described_class::MAX_MESSAGES + 5).times { |i| described_class.append(session, user_content: "m#{i}", assistant_content: "r#{i}") }

      history = described_class.history_for(session)
      expect(history.size).to eq(described_class::MAX_MESSAGES)
      expect(history.last[:content]).to eq("r#{described_class::MAX_MESSAGES + 4}")
    end

    it 'expira: grava com TTL explícito' do
      expect(store).to receive(:write).with(anything, anything, hash_including(expires_in: described_class::TTL))
      described_class.append(session, user_content: 'oi', assistant_content: 'olá')
    end

    it 'não grava nada para sessão sem dono' do
      orfa = create(:chat_session, chat_flow: flow)
      expect(described_class.append(orfa, user_content: 'oi', assistant_content: 'olá')).to be(false)
      expect(described_class.history_for(orfa)).to eq([])
    end
  end

  describe 'isolamento entre usuários' do
    it 'a memória de um não é lida pelo outro, nem com o mesmo id de sessão' do
      outro = create(:user)
      sessao_do_outro = create(:chat_session, chat_flow: flow, user: outro)

      described_class.append(session, user_content: 'segredo de A', assistant_content: 'ok')

      expect(described_class.history_for(sessao_do_outro)).to eq([])
      expect(described_class.key_for(session)).not_to eq(described_class.key_for(sessao_do_outro))
    end
  end

  describe 'fail-soft' do
    it 'Redis fora degrada para "sem memória", nunca propaga o erro' do
      allow(store).to receive(:read).and_raise(StandardError, 'redis down')
      allow(store).to receive(:write).and_raise(StandardError, 'redis down')

      expect { described_class.history_for(session) }.not_to raise_error
      expect(described_class.history_for(session)).to eq([])
      expect(described_class.append(session, user_content: 'a', assistant_content: 'b')).to be(false)
    end
  end

  describe '.clear' do
    it 'esquece a conversa' do
      described_class.append(session, user_content: 'a', assistant_content: 'A')
      described_class.clear(session)
      expect(described_class.history_for(session)).to eq([])
    end
  end
end
