class AddKindAndAgentConfigToChatFlows < ActiveRecord::Migration[8.0]
  def change
    add_column :chat_flows, :kind, :integer, default: 0, null: false
    add_column :chat_flows, :agent_config, :jsonb, default: {}, null: false
    add_index :chat_flows, :kind
  end
end
