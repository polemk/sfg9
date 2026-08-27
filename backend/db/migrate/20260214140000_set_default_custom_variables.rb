class SetDefaultCustomVariables < ActiveRecord::Migration[8.0]
  def change
    change_column_default :users, :custom_variables, from: nil, to: {}
  end
end
