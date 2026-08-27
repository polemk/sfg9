# frozen_string_literal: true

# S12 / DB-588, DB-589, DB-590, DB-367, DB-368, DB-369 — a árvore da central de
# ajuda: **Grupo → Categoria → Item**.
#
# As três tabelas do legado (`20180410131904`, `20180410132114`,
# `20180410132354`) tinham **só a PK como índice**, nenhuma FK e nenhum
# `null: false`. O que muda aqui, por tabela:
#
# **`help_groups` (DB-588 / DB-367)** — `title` único **no banco** (era só
# `validates :title, uniqueness: true`, sujeito a corrida) e **`position`
# persistida**: o legado ordenava por `title ASC` na view, então renomear um
# grupo reordenava o menu inteiro sem ninguém pedir.
#
# **`help_categories` (DB-589 / DB-368)** — **`slug` persistido, único e
# desambiguado**. No legado `normalized_title` era calculado em runtime
# (`help_category.rb:8-10`) e usado como slug de navegação: duas categorias com
# títulos que transliteram igual produziam o mesmo slug, e renomear uma
# **quebrava o deep-link da outra**. Aqui o slug é coluna, é único, e nasce
# desambiguado.
#
# **`help_items` (DB-590 / DB-369)** — PK `uuid` porque `has_rich_text
# :description` exige (`action_text_rich_texts.record_id` é `uuid NOT NULL`).
# `user_id` é o **autor** e passa a ser preservado na edição; quem alterou por
# último vai em coluna própria (`last_updated_user_id`), fechando o FE-366 —
# no legado o `user_id` viajava em campo escondido com o `current_user` e
# **editar item de outro autor reescrevia a autoria**.
#
# A coluna `help_items.description` do legado **não existe aqui**: é o D-58. Lá
# havia dois acervos (a coluna até 04/2019, o ActionText depois) e o
# `has_rich_text` sobrescrevia o leitor da coluna — nada criado depois de 04/2019
# era achado pela busca. Aqui há **um** campo, e a carga em dois passos
# (`Help::LegacyImport`) é quem reúne os dois acervos nele.
class CreateHelpTree < ActiveRecord::Migration[8.0]
  def change
    create_table :help_groups, id: :uuid, comment: 'Grupo da central de ajuda. Primeiro nível da árvore.' do |t|
      t.string :title, null: false, comment: 'Nome do grupo. Único NO BANCO — era só validação de aplicação.'
      t.integer :position, null: false, default: 0,
                           comment: 'Ordem persistida (DB-367). O legado ordenava por `title ASC` na view: renomear reordenava o menu.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'
      t.timestamps
    end

    add_index :help_groups, 'lower(title)', unique: true, name: 'index_help_groups_on_lower_title'
    add_index :help_groups, %i[position title]
    add_index :help_groups, :legacy_id, unique: true

    create_table :help_categories, id: :uuid, comment: 'Categoria da central de ajuda. Segundo nível — pertence a um grupo.' do |t|
      t.uuid :help_group_id, null: false, comment: 'Grupo dono. Era integer sem FK e sem índice.'
      t.string :title, null: false, comment: 'Nome da categoria. Único DENTRO do grupo.'
      t.string :slug, null: false,
                      comment: 'DB-368 — slug persistido e único. Era `normalized_title` calculado em runtime e usado como deep-link.'
      t.integer :position, null: false, default: 0, comment: 'Ordem persistida dentro do grupo.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'
      t.timestamps
    end

    add_index :help_categories, :slug, unique: true
    add_index :help_categories, %i[help_group_id title], unique: true
    add_index :help_categories, %i[help_group_id position]
    add_index :help_categories, :legacy_id, unique: true
    add_foreign_key :help_categories, :help_groups, column: :help_group_id, on_delete: :cascade

    create_table :help_items, id: :uuid, comment: 'Item da central de ajuda. Terceiro nível; o corpo é ActionText (fonte ÚNICA, D-58).' do |t|
      t.uuid :help_category_id, null: false, comment: 'Categoria dona. Era integer sem FK e sem índice.'
      t.string :title, null: false, comment: 'Título do item. Único DENTRO da categoria.'
      t.uuid :user_id, comment: 'AUTOR. Preservado na edição — no legado o campo escondido reescrevia a autoria a cada save (FE-366).'
      t.uuid :last_updated_user_id, comment: 'Quem alterou por último. Coluna própria justamente para não sobrescrever o autor.'
      t.integer :position, null: false, default: 0, comment: 'Ordem persistida dentro da categoria.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'
      t.timestamps
    end

    add_index :help_items, %i[help_category_id title], unique: true
    add_index :help_items, %i[help_category_id position]
    add_index :help_items, :legacy_id, unique: true
    add_foreign_key :help_items, :help_categories, column: :help_category_id, on_delete: :cascade
    add_foreign_key :help_items, :users, column: :user_id, on_delete: :nullify
    add_foreign_key :help_items, :users, column: :last_updated_user_id, on_delete: :nullify
  end
end
