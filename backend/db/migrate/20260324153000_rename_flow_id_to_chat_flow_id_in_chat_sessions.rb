class RenameFlowIdToChatFlowIdInChatSessions < ActiveRecord::Migration[8.0]
  def change
    if column_exists?(:chat_sessions, :flow_id)
      rename_column :chat_sessions, :flow_id, :chat_flow_id
    end
  end
end
