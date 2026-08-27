# frozen_string_literal: true

class AddLinkTokenToLoginCodes < ActiveRecord::Migration[7.1]
  def change
    add_column :login_codes, :link_token, :string
    add_index :login_codes, :link_token, unique: true
  end
end
