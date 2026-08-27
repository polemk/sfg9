class CreateAgentRuns < ActiveRecord::Migration[8.0]
  # GOAT v2 / S1.1 — telemetria por turno do agente de IA.
  #
  # Tabela append-only que registra cada chamada de Ai::AgentService:
  # provider/model, canal, tools chamadas, chunks recuperados (futuro RAG),
  # latência, uso de tokens e status. Base de evals (S1.4) e cutover (S7.1).
  #
  # FKs intencionalmente como bigint simples (sem foreign_key): histórico
  # de telemetria deve sobreviver à exclusão de session/flow.
  #
  # NOTA DO TRIM (Phase 1b, Bloco 6): a coluna `lead_id` (e o índice
  # `[lead_id, created_at]`) saíram com o AI9-006. A tabela é do AI9-007
  # (telemetria do agente, MANTIDA), por isso a migration foi editada, não
  # apagada. Cumpre a parte de `agent_run.lead_id` da 8.3 da tasks.md.
  #
  # NOTA DO TRIM (Bloco 7): a coluna `operation_id` e o índice
  # `[operation_id, created_at]` saíram com o AI9-014, pelo mesmo motivo. Com
  # isso a 8.3 da tasks.md fica cumprida por inteiro.
  def change
    create_table :agent_runs do |t|
      t.bigint   :chat_session_id
      t.bigint   :chat_flow_id

      t.string   :provider                       # openai / anthropic / google
      t.string   :model                          # gpt-4o, claude-3-5-sonnet, etc.
      t.string   :channel                        # waba / evolution / instagram / messenger / web / chat

      t.jsonb    :tools_called,     default: []  # [{name, success, duration_ms}]
      t.jsonb    :retrieval_chunks, default: []  # [{source_label, chunk_index, score}] (S2)
      t.jsonb    :token_usage,      default: {}  # {prompt, completion, total}

      t.integer  :latency_ms
      t.integer  :loop_count, default: 0         # multi-hop de tools (MAX_TOOL_LOOPS)

      t.string   :status                         # success / error / partial
      t.text     :error

      t.timestamps
    end

    add_index :agent_runs, %i[chat_flow_id created_at]
    add_index :agent_runs, :status
    add_index :agent_runs, :created_at
  end
end
