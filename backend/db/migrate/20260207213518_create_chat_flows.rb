class CreateChatFlows < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_flows, if_not_exists: true do |t|
      t.string :name
      t.string :trigger_keyword
      t.jsonb :definition
      t.boolean :published

      t.timestamps
    end
  end
end
