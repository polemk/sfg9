# frozen_string_literal: true

# S11 / DEC-12, DB-133 — **proveniência do registro na base do legado**.
#
# Padrão já usado por `projects`, `carriers`, `providers`, `renegotiations` e
# companhia: o id numérico da origem fica guardado, com índice **único**, e é a
# chave natural que torna a carga do ETL idempotente (`find_or_initialize_by`
# em vez de `create`). Sem ela, rodar o ETL duas vezes duplicaria a árvore
# inteira de padrões.
#
# **`legacy_id` é preservado e nunca reusado** — não é `id`, é histórico.
class AddLegacyIdToAvailabilityTables < ActiveRecord::Migration[8.0]
  def change
    add_column :availability_templates, :legacy_id, :bigint,
               comment: 'DEC-12 — proveniência do registro na base do legado (availability_templates.id).'
    add_index :availability_templates, :legacy_id, unique: true

    add_column :availability_entries, :legacy_id, :bigint,
               comment: 'DEC-12 — proveniência do registro na base do legado (availability_entries.id).'
    add_index :availability_entries, :legacy_id, unique: true
  end
end
