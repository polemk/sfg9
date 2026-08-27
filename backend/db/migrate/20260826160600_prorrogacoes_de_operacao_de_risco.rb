# frozen_string_literal: true

# S5 / DB-237 — **prorrogações de operação** (`RiskOperationExtension`).
#
# O esquema nasce aqui, junto do resto do bloco; **S7 consome** e escreve o
# comportamento (o `after_create` que empurra o vencimento da operação).
#
# Duas garantias que o legado não tinha:
#
# 1. **FK `ON DELETE CASCADE` + índice.** A prorrogação é histórico de UMA
#    operação: sem a operação ela não significa nada. No legado não há FK
#    nenhuma e a tabela não tem um único índice.
# 2. **Check `new_due_date > original_due_date`.** Prorrogar para uma data igual
#    ou anterior não é prorrogação — é encurtar prazo por engano, e o
#    `after_create` do legado aplicaria o valor à operação sem reclamar.
class ProrrogacoesDeOperacaoDeRisco < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_operation_extensions, id: :uuid, default: -> { 'gen_random_uuid()' },
                                             comment: 'Prorrogação de vencimento de uma operação de risco. Esquema da S5 (DB-237); o comportamento é da S7.' do |t|
      t.uuid :risk_operation_id, null: false
      t.uuid :user_id, null: false
      t.date :original_due_date, null: false, comment: 'Vencimento da operação NO MOMENTO da prorrogação — copiado no before_validation.'
      t.date :new_due_date, null: false
      t.string :observation

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :risk_operation_extensions, :risk_operation_id
    add_index :risk_operation_extensions, :legacy_id, unique: true

    add_foreign_key :risk_operation_extensions, :risk_operations, column: :risk_operation_id, on_delete: :cascade
    add_foreign_key :risk_operation_extensions, :users, column: :user_id

    add_check_constraint :risk_operation_extensions, 'new_due_date > original_due_date',
                         name: 'risk_operation_extensions_forward_only_check'
  end
end
