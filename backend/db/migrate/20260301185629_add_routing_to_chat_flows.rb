class AddRoutingToChatFlows < ActiveRecord::Migration[8.0]
  def change
    add_column :chat_flows, :mapped_routes, :string, array: true, default: []
    add_column :chat_flows, :override_active_chat, :boolean, default: false
  end
end
