class AddCredentialIdToChatFlows < ActiveRecord::Migration[8.0]
  def change
    add_reference :chat_flows, :credential, null: true, foreign_key: true
  end
end
