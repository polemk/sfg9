# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentService do
  let(:credential) do
    Credential.create!(name: 'Test Anthropic', provider: 'anthropic', api_key: 'sk-test-key-12345678')
  end
  let(:flow) do
    create(:chat_flow, :ai_agent, agent_config: {
      'system_prompt' => 'You are a test assistant.',
      'credential_id' => credential.id,
      'model' => 'claude-3-5-sonnet-20241022',
      'welcome_message' => 'Hello!'
    })
  end
  let(:session) { create(:chat_session, chat_flow: flow) }

  before do
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200, body: {
        content: [{ type: 'text', text: 'AI test response' }],
        stop_reason: 'end_turn'
      }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '.respond' do
    # Bloco 7 do trim (AI9-014): o contexto 'with RAG Context Injection' saiu com o
    # `OperationKnowledge` — era a base de conhecimento injetada no system prompt.

    # Bloco 6 do trim (AI9-006): estes dois contextos afirmavam a PERSISTÊNCIA do
    # turno em `lead.messages` (`LeadMessage`), que saiu com a feature.
    # Bloco 8 / DEC-20: o armazém voltou — memória/Redis, sem tabela. Ver o
    # contexto 'memória de conversa' abaixo e `conversation_memory_spec.rb`.

    # ----------------------------------------------------------------
    # Bloco 8 / DEC-20 — o assistente lembra do turno anterior.
    #
    # `test.rb` usa `:null_store`, então aqui também trocamos por `MemoryStore`:
    # sem isso o exemplo passaria por não guardar nada, que é o defeito.
    # ----------------------------------------------------------------
    context 'memória de conversa (DEC-20)' do
      let(:user) { create(:user) }
      let(:session) { create(:chat_session, chat_flow: flow, user: user) }
      let(:store) { ActiveSupport::Cache::MemoryStore.new }
      # Corpos enviados ao provider, na ordem — é como provamos o que ele viu.
      let(:enviados) { [] }

      before do
        allow(Rails).to receive(:cache).and_return(store)

        stub_request(:post, 'https://api.anthropic.com/v1/messages').to_return do |request|
          enviados << JSON.parse(request.body)
          {
            status: 200,
            body: { content: [{ type: 'text', text: 'AI test response' }], stop_reason: 'end_turn' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          }
        end
      end

      it 'manda o turno corrente ao provider' do
        described_class.respond(session, 'meu nome é Vinícius')

        expect(enviados.last['messages'].last['content'].to_s).to include('meu nome é Vinícius')
      end

      it 'guarda pergunta e resposta para o próximo turno' do
        described_class.respond(session, 'meu nome é Vinícius')

        expect(Ai::ConversationMemory.history_for(session)).to eq([
          { role: 'user',      content: 'meu nome é Vinícius' },
          { role: 'assistant', content: 'AI test response' }
        ])
      end

      it 'LEMBRA: o 2º turno chega ao provider com o 1º junto' do
        described_class.respond(session, 'meu nome é Vinícius')
        described_class.respond(session, 'qual é o meu nome?')

        conteudos = enviados.last['messages'].map { |m| m['content'].to_s }
        expect(conteudos).to include(a_string_including('meu nome é Vinícius'))
        expect(conteudos).to include(a_string_including('AI test response'))
        expect(conteudos.last).to include('qual é o meu nome?')
      end

      it 'não vaza a conversa de um usuário para o outro' do
        described_class.respond(session, 'segredo de A')

        outro = create(:user)
        sessao_do_outro = create(:chat_session, chat_flow: flow, user: outro)
        expect(Ai::ConversationMemory.history_for(sessao_do_outro)).to eq([])
      end

      it 'guarda o texto LIMPO — o marcador [opcoes: ...] nunca volta ao modelo' do
        allow_any_instance_of(Ai::Providers::AnthropicProvider)
          .to receive(:chat_completion).and_return('Claro! [opcoes: Sim | Não]')

        described_class.respond(session, 'ajuda?')

        gravado = Ai::ConversationMemory.history_for(session).last[:content]
        expect(gravado).not_to include('[opcoes')
        expect(gravado).to include('Claro!')
      end
    end
    context 'with text-only input (no tools)' do
      it 'returns the AI response' do
        responses = described_class.respond(session, 'Hello AI')

        expect(responses).to be_an(Array)
        expect(responses.first[:content]).to eq('AI test response')
      end
    end

    context 'with image_data' do
      let(:image_data) { { base64: 'aW1hZ2VfZGF0YQ==', mime_type: 'image/jpeg' } }

      it 'aceita imagem sem quebrar e responde' do
        responses = described_class.respond(session, 'Describe this', image_data: image_data)

        expect(responses).to be_an(Array)
        expect(responses.first[:content]).to eq('AI test response')
      end

      it 'handles nil caption gracefully' do
        responses = described_class.respond(session, nil, image_data: image_data)

        expect(responses).to be_an(Array)
      end
    end

    # Bloco 6 do trim (AI9-006): os contextos `extract_lead` (tool `capture_lead`
    # gravando no `Lead`) saíram com a capability `lead_capture`.

    # ----------------------------------------------------------------
    # GOAT v2 / S1.2 — telemetria por turno (AgentRun, fail-soft)
    # ----------------------------------------------------------------
    context 'instrumentation (S1.2 — AgentRun)' do
      it 'cria um AgentRun de sucesso com latency, provider e model' do
        expect { described_class.respond(session, 'Olá') }
          .to change(AgentRun, :count).by(1)

        run = AgentRun.last
        expect(run.status).to eq('success')
        expect(run.provider).to eq('anthropic')
        expect(run.model).to eq('claude-3-5-sonnet-20241022')
        expect(run.chat_session_id).to eq(session.id)
        expect(run.chat_flow_id).to eq(flow.id)
        expect(run.latency_ms).to be >= 0
        expect(run.loop_count).to eq(0)
        expect(run.tools_called).to eq([])
        expect(run.error).to be_nil
      end

      # Bloco 8 / DEC-20: `channel` vinha de `lead.source_type` e ficou nulo com o
      # AI9-006. Volta como CONSTANTE — o DEC-13.2 define um uso só (assistente
      # interno no console) e portanto um canal só.
      it 'grava channel=console — o único canal do uso definido no DEC-13.2' do
        described_class.respond(session, 'Olá')

        expect(AgentRun.last.channel).to eq('console')
        expect(described_class::CHANNEL).to eq('console')
      end

      it 'cria um AgentRun com status=error e mensagem quando o provider falha' do
        allow_any_instance_of(Ai::Providers::AnthropicProvider)
          .to receive(:chat_completion).and_raise(StandardError, 'Boom!')

        responses = described_class.respond(session, 'Olá')
        # Resposta amigável ao usuário não deve quebrar
        expect(responses.first[:content]).to include('erro')

        run = AgentRun.last
        expect(run.status).to eq('error')
        expect(run.error).to include('StandardError')
        expect(run.error).to include('Boom!')
        expect(run.latency_ms).to be >= 0
      end

      it 'não bloqueia a resposta ao usuário se AgentRun.create! falhar (fail-soft)' do
        allow(AgentRun).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'simulated DB error')

        responses = described_class.respond(session, 'Olá')

        expect(responses).to be_an(Array)
        expect(responses.first[:content]).to eq('AI test response')
      end
    end
  end
end
