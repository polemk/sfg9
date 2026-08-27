# frozen_string_literal: true

# S0 / DB-080 — a tabela `projects` nasce AQUI como esquema, só para servir de FK
# a `memberships` e a `users.current_project_id` (decisão DS0-1 do design de S0).
#
# Endpoint, tela e efeitos colaterais da criação de projeto são da fatia S4.
# Sem a tabela não há FK de participação; sem participação não há escopo; e sem
# escopo a S0 travaria a si mesma.
class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects, id: :uuid, comment: 'Projeto Safegold — a unidade de escopo (tenant) do sistema. Contrato C1.' do |t|
      t.string :name, null: false,
                      comment: 'Nome do projeto. Equivale a `projects.formal` no legado sfg.'
      t.string :slug, null: false,
                      comment: 'Identificador legível e único. Equivale a `projects.smart_id` no legado sfg.'
      t.uuid :user_id, null: false,
                       comment: 'Dono do projeto. Protegido contra remoção de participação (DEC-18.5).'
      t.uuid :segment_id,
             comment: 'FK LÓGICA para `segments`. A tabela de segmentos nasce em S1 — a constraint real é acrescentada lá.'
      t.boolean :is_active, null: false, default: true,
                            comment: 'Projeto ativo. `null: false` de propósito: o legado usava integer nullable e o filtro caía em NULL.'
      t.integer :legacy_id,
                comment: 'DEC-12 — proveniência do registro na base do legado. Preservado, nunca reusado como chave.'

      t.timestamps
    end

    add_index :projects, :slug, unique: true
    add_index :projects, :user_id
    add_index :projects, :segment_id
    add_index :projects, :is_active
    add_index :projects, :legacy_id, unique: true

    add_foreign_key :projects, :users, column: :user_id
  end
end
