# frozen_string_literal: true

# S0 / BE-042, DB-503 — a permissão **do papel**.
#
# Por que esta tabela existe além de `permissions` + `user_permissions`: sem um
# lugar para a concessão *por papel*, as tarefas 3.6 e 3.8 (revogar permissão de
# um papel; `PUT /user_types/:id/permissions/:key`) não têm onde escrever, e o
# **D-35** voltaria — no legado a `Role` CLONAVA as 17 abilities no momento da
# atribuição, então alterar a permissão do papel não alcançava quem já existia.
#
# Aqui a permissão é **consulta**, nunca cópia: papel → default (esta tabela),
# `user_permissions` → override do usuário. Resolvida a cada request por
# `Authorization::PermissionResolver`. O D-35 desaparece **por construção**.
#
# A `Ability` polimórfica do legado (17 linhas × cada papel **e** cada usuário)
# não é replicada: das 17 abilities só `user_is_readonly` sobrevive (DEC-18.6).
class CreateUserTypePermissions < ActiveRecord::Migration[8.0]
  def change
    create_table :user_type_permissions,
                 comment: 'Permissão padrão de um papel. Resolvida por consulta a cada request — nunca clonada no usuário (fecha D-35).' do |t|
      t.uuid :user_type_id, null: false
      t.bigint :permission_id, null: false
      t.boolean :granted, null: false, default: true,
                          comment: 'Booleano explícito em vez de "linha existe = concedido": revogar precisa ser um ato auditável, não um DELETE mudo.'

      t.timestamps
    end

    add_index :user_type_permissions, %i[user_type_id permission_id], unique: true
    add_index :user_type_permissions, :permission_id

    add_foreign_key :user_type_permissions, :user_types, column: :user_type_id, on_delete: :cascade
    add_foreign_key :user_type_permissions, :permissions, column: :permission_id, on_delete: :cascade
  end
end
