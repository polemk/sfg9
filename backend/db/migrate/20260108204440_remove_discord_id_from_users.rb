class RemoveDiscordIdFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :discord_id, :string
  end
end
