# NOTA DO TRIM (Phase 1b, Bloco 6): esta migration mexia em DUAS tabelas de
# features diferentes — `chat_flows` (AI9-007, MANTIDO) e `leads` (AI9-006,
# removido). Por isso foi editada em vez de apagada: saíram
# `leads.custom_fields` e o índice GIN correspondente.
class AddFlowIntelligenceColumns < ActiveRecord::Migration[8.0]
  def change
    add_column :chat_flows, :keywords, :string, array: true, default: []
    add_column :chat_flows, :persona_name, :string
    add_column :chat_flows, :persona_avatar, :string
    
    add_index :chat_flows, :keywords, using: :gin
  end
end
