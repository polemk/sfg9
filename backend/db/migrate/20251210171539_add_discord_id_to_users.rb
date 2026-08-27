class AddDiscordIdToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :discord_id, :string
  end
end
