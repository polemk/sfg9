class AddContextualRoutingToChatFlows < ActiveRecord::Migration[8.0]
  def change
    add_column :chat_flows, :target_user_type, :string
    add_column :chat_flows, :target_route_path, :string
  end
end
