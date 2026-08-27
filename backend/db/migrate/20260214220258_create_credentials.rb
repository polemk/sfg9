class CreateCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :credentials do |t|
      t.string :name, null: false
      t.string :provider, null: false
      t.text :api_key, null: false

      t.timestamps
    end

    add_index :credentials, :name, unique: true
    add_index :credentials, :provider
  end
end
