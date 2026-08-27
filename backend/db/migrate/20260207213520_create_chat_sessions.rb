# NOTA DO TRIM (Phase 1b, Bloco 6): esta migration nasceu com
# `t.references :lead, null: false, foreign_key: true`. O `Lead` era o AI9-006
# (leads/omnichannel), removido em bloco; a `chat_sessions` é do AI9-007
# (chatbot, MANTIDO), por isso a migration foi editada em vez de apagada.
# Com isso a 8.3 da tasks.md (`chat_session.lead_id`) fica cumprida aqui.
class CreateChatSessions < ActiveRecord::Migration[8.0]
  def up
    return if table_exists?(:chat_sessions)

    create_table :chat_sessions do |t|
      t.references :chat_flow, null: false, foreign_key: { to_table: :chat_flows }
      t.string :current_step_id
      t.jsonb :context

      t.timestamps
    end
  end

  def down
    drop_table :chat_sessions, if_exists: true
  end
end
