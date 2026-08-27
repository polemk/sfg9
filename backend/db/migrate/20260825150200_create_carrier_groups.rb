# frozen_string_literal: true

# S3 / DB-063, DB-553, OPS-058 — grupos de portadores.
#
# **`carriers_count` nasce `null: false, default: 0`** e passa a ser mantido pelo
# `counter_cache` do ActiveRecord. No legado a coluna era `integer` nullable e a
# contagem divergia da lista — e era ela que decidia se o botão de exclusão
# aparecia. O botão sumia, e a exclusão passava assim mesmo.
#
# **`integration_key` é acréscimo desta migração**, e é deliberado: o grupo é o
# único dos cinco catálogos que o legado deixou sem chave, e sem ela ele seria o
# único que não busca nem ordena pela mesma coluna que os outros quatro. É a
# mesma forma, não uma feature nova — a coluna é derivada do título e congelada,
# exatamente como nos demais.
#
# `title` **não** ganha unicidade: o legado não a tem, e este catálogo herda a
# mesma política do portador ("Cloud #7036" — derivados legítimos com o mesmo
# nome). O índice existe para a busca e a ordenação, não para travar.
class CreateCarrierGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :carrier_groups, id: :uuid, default: -> { 'gen_random_uuid()' }, comment: 'Grupo de portadores. Catálogo GLOBAL — sem escopo de projeto (C1, regra 4).' do |t|
      t.string :title, null: false, comment: 'Nome do grupo.'
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois (DC-22).'
      t.integer :carriers_count, null: false, default: 0,
                                 comment: 'counter_cache dos portadores do grupo (OPS-058). Era nullable e divergia da lista.'
      t.boolean :is_active, null: false, default: true, comment: 'Grupo ativo.'
      t.uuid :user_id, comment: 'Autor do cadastro, vindo da SESSÃO. Informativo.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência na base do legado.'

      t.timestamps
    end

    add_index :carrier_groups, :title
    add_index :carrier_groups, :integration_key
    add_index :carrier_groups, :is_active
    add_index :carrier_groups, :legacy_id, unique: true
    add_index :carrier_groups, :user_id

    add_foreign_key :carrier_groups, :users, column: :user_id, on_delete: :nullify
  end
end
