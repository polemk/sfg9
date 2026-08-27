# frozen_string_literal: true

# S0 / OPS-005, OPS-006 — o "membro padrão" do legado.
#
# `livetat_auth_users.is_default_member` (integer 0/1) marcava quem entra
# automaticamente em **todo** projeto. Aqui vira booleano com `null: false`: o
# legado tinha um integer nullable e o `where(is_default_member: 1)` deixava o
# NULL de fora sem que ninguém percebesse.
class AddIsDefaultMemberToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :is_default_member, :boolean, null: false, default: false,
                                                     comment: 'Entra automaticamente em todo projeto novo. Dispara DefaultMemberJob SÓ quando muda.'
    add_index :users, :is_default_member, where: 'is_default_member'
  end
end
