# frozen_string_literal: true

class CreateFlowExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :flow_executions do |t|
      t.references :chat_session, null: false, foreign_key: true
      t.references :chat_flow, null: false, foreign_key: true
      t.string :node_id, null: false
      t.string :node_type, null: false
      t.jsonb :input_data, default: {}
      t.jsonb :output_data, default: {}
      t.jsonb :context_snapshot, default: {}

      t.timestamps
    end

    add_index :flow_executions, :node_id
    add_index :flow_executions, :node_type
    add_index :flow_executions, :created_at
  end
end
