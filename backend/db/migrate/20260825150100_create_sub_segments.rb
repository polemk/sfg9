# frozen_string_literal: true

# S3 / DB-066, DB-551 — o catálogo global de **subsegmentos**.
#
# **DC-13: `sub_segments` NÃO ganha FK para `segments`.** Apesar do nome, o
# legado não tem associação nenhuma entre os dois: são duas listas planas
# independentes, e `projects` aponta para cada uma por uma coluna própria.
# Criar a hierarquia agora exigiria **inventar** o mapeamento para os dados
# existentes — fica registrado como candidato a feature futura.
#
# Se você veio "consertar" acrescentando `segment_id`: pare. A tabela é a mesma
# forma de `segments` de propósito, e o motivo está escrito aqui.
class CreateSubSegments < ActiveRecord::Migration[8.0]
  def change
    create_table :sub_segments, id: :uuid, default: -> { 'gen_random_uuid()' }, comment: 'Subsegmento de atuação. Catálogo GLOBAL e INDEPENDENTE de `segments` (DC-13).' do |t|
      t.string :title, null: false, comment: 'Nome do subsegmento. Único no banco.'
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois (DC-22).'
      t.boolean :is_active, null: false, default: true, comment: 'Subsegmento ativo. Era integer nullable no legado.'
      t.uuid :user_id, comment: 'Autor do cadastro, vindo da SESSÃO. Informativo — nunca consultado para autorizar.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência na base do legado.'

      t.timestamps
    end

    add_index :sub_segments, :title, unique: true
    add_index :sub_segments, :integration_key
    add_index :sub_segments, :is_active
    add_index :sub_segments, :legacy_id, unique: true
    add_index :sub_segments, :user_id

    add_foreign_key :sub_segments, :users, column: :user_id, on_delete: :nullify
  end
end
