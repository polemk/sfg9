# frozen_string_literal: true

# S3 / DB-064, DB-065, DB-550, OPS-053 — o catálogo global de **segmentos**.
#
# Catálogo GLOBAL (contrato C1, regra 4 de `§0.6`): não tem `project_id`, não
# inclui `ProjectScoped` e nenhum endpoint desta fatia chama `current_project!`.
# O menu esconde a tela de administração do catálogo, não o dado do catálogo
# (DEC-18.4).
#
# Três coisas mudam em relação ao legado, e as três são defeito medido:
#
# 1. **`title` passa a ser único NO BANCO.** No legado a unicidade existia só na
#    validação do model — e é do `segment_id` fixo em 1 (D-26) que a S4 se
#    defende quando reseta um projeto.
# 2. **`user_id` é anulável.** No legado `validates :user_id, presence: true` +
#    `user_id` FORA do `permit` faziam a criação falhar **100% das vezes**
#    (D-21). Aqui o autor vem da SESSÃO e é informativo: seed e ETL gravam sem
#    autor, e isso não pode reprovar o registro.
# 3. **`is_active` é boolean.** Era `integer default 1`, e o filtro caía em NULL.
class CreateSegments < ActiveRecord::Migration[8.0]
  def change
    create_table :segments, id: :uuid, default: -> { 'gen_random_uuid()' }, comment: 'Segmento de atuação do cliente. Catálogo GLOBAL — sem escopo de projeto (C1, regra 4).' do |t|
      t.string :title, null: false,
                       comment: 'Nome do segmento. Único no banco (DB-064) — fecha o caminho do D-26.'
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois (DC-22).'
      t.boolean :is_active, null: false, default: true,
                            comment: 'Segmento ativo. Era integer nullable no legado.'
      t.uuid :user_id,
             comment: 'Autor do cadastro, vindo da SESSÃO (BE-076). Informativo — nunca consultado para autorizar.'
      t.integer :legacy_id,
                comment: 'DEC-12 — proveniência na base do legado. Preservado, nunca reusado como chave.'

      t.timestamps
    end

    add_index :segments, :title, unique: true
    add_index :segments, :integration_key
    add_index :segments, :is_active
    add_index :segments, :legacy_id, unique: true
    add_index :segments, :user_id

    add_foreign_key :segments, :users, column: :user_id, on_delete: :nullify
  end
end
