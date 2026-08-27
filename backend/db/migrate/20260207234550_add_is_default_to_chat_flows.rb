class AddIsDefaultToChatFlows < ActiveRecord::Migration[8.0]
  def change
    add_column :chat_flows, :is_default, :boolean, default: false, null: false
    add_index :chat_flows, :is_default, where: "is_default = true", unique: true
  end
end
