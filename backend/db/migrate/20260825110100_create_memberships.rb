# frozen_string_literal: true

# S0 / DB-086, DB-011, DB-545 — participação de usuário em projeto.
#
# É a peça 1 do contrato C1: **a verdade sobre quem enxerga o quê**. O
# `users.current_project_id` é só uma preferência; quem autoriza é a linha desta
# tabela, revalidada a cada request.
#
# `role` é rótulo DESCRITIVO e **nunca** é consultado para autorizar (DEC-18.6 /
# Q-A2). A autorização tem uma dimensão só: papel global (`users.user_type_id`)
# + existência de participação.
class CreateMemberships < ActiveRecord::Migration[8.0]
  ROLES = %w[responsavel participante coordenador gestor].freeze

  def change
    create_table :memberships, id: :uuid, comment: 'Participação de um usuário num projeto. Peça 1 do contrato C1.' do |t|
      t.uuid :user_id, null: false, comment: 'Usuário participante.'
      t.uuid :project_id, null: false, comment: 'Projeto ao qual o usuário pertence.'
      t.string :role, null: false, default: 'participante',
                      comment: 'Rótulo DESCRITIVO da função no projeto. NUNCA consultado para autorizar (DEC-18.6).'
      t.integer :legacy_id,
                comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    # O índice único é o que impede participação duplicada — e é ele que faz o
    # `find_or_create` de participação ser seguro sob concorrência.
    add_index :memberships, %i[user_id project_id], unique: true
    add_index :memberships, :project_id
    add_index :memberships, :legacy_id, unique: true

    add_foreign_key :memberships, :users, column: :user_id, on_delete: :cascade
    add_foreign_key :memberships, :projects, column: :project_id, on_delete: :cascade

    # Enum estável no banco: um valor fora da lista é erro de escrita, não um
    # rótulo silencioso que ninguém consegue interpretar depois.
    add_check_constraint :memberships,
                         "role IN (#{ROLES.map { |r| "'#{r}'" }.join(', ')})",
                         name: 'memberships_role_enum'
  end
end
