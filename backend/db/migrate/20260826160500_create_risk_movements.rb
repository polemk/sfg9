# frozen_string_literal: true

# S5 / DB-236 — **movimentos de risco** (`RiskMovement`).
#
# O esquema nasce aqui, junto do resto do bloco de risco, porque as FKs precisam
# existir antes de a S7 escrever o comportamento. **S7 consome**: recálculo de
# cadeia, movimento espelho de transferência, CRUD e telas são de lá.
#
# Duas escolhas de esquema que mudam comportamento se erradas:
#
# 1. **`order` vira `sequence`.** `order` é palavra reservada em SQL; no legado a
#    coluna se chama `order` e sobrevive só porque o Rails a cita. Qualquer SQL
#    escrito à mão contra ela quebra. O payload da API expõe `sequence`.
# 2. **O índice é (`risk_operation_id`, `date`, `created_at`)** — exatamente a
#    ordenação do recálculo (`movements.order(date: :asc, created_at: :asc)`,
#    `risk_operation.rb:103`) e da leitura de saldo por data (`:93`). Um índice
#    por `id` faria o recálculo degradar **e** convidaria alguém a reordenar por
#    `id`, o que **muda saldo**: a ordem dos movimentos é a ordem em que os
#    sinais `+1`/`−1` se acumulam.
#
# `company_id`, `carrier_id` e `project_id` continuam **colunas carimbadas**,
# copiadas da operação no `before_validation` — é o que o legado faz e é o que os
# relatórios já leem. Não são a fonte de verdade do escopo (a operação é), e por
# isso não há índice composto de tenant aqui.
class CreateRiskMovements < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_movements, id: :uuid, default: -> { 'gen_random_uuid()' },
                                  comment: 'Movimento de uma operação de risco. Esquema da S5 (DB-236); o comportamento é da S7.' do |t|
      t.uuid :user_id
      t.uuid :risk_operation_id, null: false
      t.uuid :movement_type_id, null: false

      t.integer :sequence, comment: 'Ordem do movimento na cadeia, recalculada a cada save da operação. Era `order` no legado — palavra reservada em SQL.'
      t.date :date, null: false, comment: 'Data do movimento. Tem de cair entre emissão e vencimento da operação (validação de model).'

      t.decimal :movement_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :balance, precision: 14, scale: 2, null: false, default: 0,
                          comment: 'Saldo ACUMULADO depois deste movimento. É o que Risk::Calculator#balance_on lê.'

      t.string :observation

      # Carimbos copiados da operação (before_validation do legado).
      t.uuid :project_id, null: false
      t.uuid :company_id, null: false
      t.uuid :carrier_id, null: false

      t.uuid :receivable_id, comment: 'Recebível que originou o movimento (S6).'
      t.uuid :pair_id, comment: 'Movimento espelho da transferência entre pré e antecipação (S7).'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    # **Obrigatório**: é a ordenação literal do recálculo e da leitura de saldo.
    add_index :risk_movements, %i[risk_operation_id date created_at],
              name: 'index_risk_movements_on_operation_date_created'
    add_index :risk_movements, :movement_type_id
    add_index :risk_movements, :pair_id
    add_index :risk_movements, :receivable_id
    add_index :risk_movements, :project_id
    add_index :risk_movements, :legacy_id, unique: true

    # O movimento morre com a operação (`dependent: :destroy` no legado): ele não
    # existe fora dela e um movimento órfão corromperia o saldo de nada.
    add_foreign_key :risk_movements, :risk_operations, column: :risk_operation_id, on_delete: :cascade
    add_foreign_key :risk_movements, :risk_movement_types, column: :movement_type_id
    add_foreign_key :risk_movements, :risk_movements, column: :pair_id, on_delete: :nullify
    add_foreign_key :risk_movements, :projects, column: :project_id
    add_foreign_key :risk_movements, :companies, column: :company_id
    add_foreign_key :risk_movements, :carriers, column: :carrier_id
    add_foreign_key :risk_movements, :users, column: :user_id
  end
end
