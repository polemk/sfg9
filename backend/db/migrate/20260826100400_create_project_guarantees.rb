# frozen_string_literal: true

# S4 / DB-083, DB-557 — **garantias do projeto**.
#
# Três correções de tipo em relação ao legado
# (`db/migrate/20220627125026_create_project_guarantees.rb`):
#
# 1. **`observation` vira `text`.** Era `string` (255) com um `textarea` na tela:
#    o operador escrevia à vontade e o banco truncava calado.
# 2. **`value` vira `decimal(14,2)`** — o padrão monetário desta migração. Era
#    `decimal(15,2)`; a escala não muda, a precisão passa a ser a mesma de
#    `carriers.net_worth` e das demais colunas de dinheiro.
# 3. **FKs reais e índices.** O legado não tinha nenhum dos dois, apesar de a
#    tela ordenar e filtrar por `carrier_id` e `guarantee_type_id`.
#
# `user_id` é o autor, vindo da SESSÃO. No legado o `permit` aceitava `:user_id`
# **e** `:project_id` do corpo, e o `update` não sobrescrevia nenhum dos dois —
# era troca de dono e de tenant por campo escondido de formulário (D-23).
class CreateProjectGuarantees < ActiveRecord::Migration[8.0]
  def change
    create_table :project_guarantees, id: :uuid, default: -> { 'gen_random_uuid()' },
                                      comment: 'Garantia dada por um portador dentro de um projeto. Escopada por projeto (C1).' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto dono. Obrigatório (C1).'
      t.uuid :carrier_id, null: false,
                          comment: 'Portador que dá a garantia. SÓ portadores CONECTADOS ao projeto são aceitos (BE-119).'
      t.uuid :guarantee_type_id, null: false, comment: 'Tipo de garantia. Catálogo GLOBAL da S3.'
      t.uuid :user_id, comment: 'Autor do cadastro, vindo da SESSÃO. O `user_id` do corpo é ignorado (D-23).'
      t.string :title, null: false, comment: 'Descrição curta da garantia.'
      t.decimal :value, precision: 14, scale: 2, null: false, default: 0.0,
                        comment: 'Valor garantido. decimal(14,2) — o padrão monetário desta migração.'
      t.text :observation,
             comment: 'Observação. TEXT (era string(255) com textarea na tela: o texto era truncado em silêncio).'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :project_guarantees, :project_id
    add_index :project_guarantees, :carrier_id
    add_index :project_guarantees, :guarantee_type_id
    add_index :project_guarantees, :user_id
    add_index :project_guarantees, :title
    add_index :project_guarantees, :legacy_id, unique: true

    add_foreign_key :project_guarantees, :projects, column: :project_id
    add_foreign_key :project_guarantees, :carriers, column: :carrier_id
    add_foreign_key :project_guarantees, :project_guarantee_types, column: :guarantee_type_id
    add_foreign_key :project_guarantees, :users, column: :user_id, on_delete: :nullify
  end
end
