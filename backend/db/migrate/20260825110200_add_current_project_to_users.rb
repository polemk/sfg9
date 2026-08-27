# frozen_string_literal: true

# S0 / DB-087, DB-397 — peça 2 do contrato C1: o projeto corrente, resolvido no
# SERVIDOR. Nunca cookie, nunca campo escondido de formulário — é o que fecha o
# D-28 (o legado deixava o projeto corrente sob controle do cliente).
#
# Aditiva e nullable de propósito: é coluna nova numa tabela compartilhada, e
# usuário sem nenhuma participação simplesmente não tem projeto corrente.
#
# ATENÇÃO ao ler o resto do código: esta coluna é PREFERÊNCIA, não autorização.
# `current_project!` revalida o valor contra `memberships` a cada request.
class AddCurrentProjectToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :current_project_id, :uuid,
               comment: 'Preferência de projeto corrente. NÃO é autorização: revalidada contra memberships a cada request (C1).'
    add_index :users, :current_project_id

    # `on_delete: :nullify` — apagar um projeto não pode derrubar o usuário.
    add_foreign_key :users, :projects, column: :current_project_id, on_delete: :nullify
  end
end
