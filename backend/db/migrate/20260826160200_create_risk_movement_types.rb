# frozen_string_literal: true

# S5 / DB-234 — **tipos de movimentação de risco** (`RiskMovementType`).
# Catálogo GLOBAL.
#
# Cada movimento de uma operação (S7) aponta para um destes tipos, e o
# `credit_type` é o **sinal** que entra no recálculo do saldo: `D` soma `+1`,
# `C` soma `−1` (`../sfg/app/models/risk_movement_type.rb:53-61`). Um valor
# fora de `('C','D')` faria `parse_credit_type_value` devolver **0** e o
# movimento simplesmente não mexeria no saldo — em silêncio. Por isso o
# **check constraint**: o banco recusa, não o `case` do Ruby.
#
# Duas mudanças em relação ao legado:
#
# 1. **`credit_type_description` NÃO é coluna.** No legado era gravada por
#    `before_validation … on: [:create]` a partir do `credit_type` e nunca mais
#    recalculada: mudar o tipo de crédito na edição deixava a descrição errada
#    para sempre, e a ordenação da tela ordenava por ela
#    (`get_ordering_key("credit_type") => "credit_type_description"`). Aqui é
#    **derivada** do enum, e a ordenação é por `credit_type` — que ordena `C`
#    antes de `D`, exatamente como "Crédito" antes de "Débito".
# 2. **`integration_key` é única.** É por ela que `RiskMovementType.release`,
#    `.transfer_out` e `.transfer_in` resolvem (decisão B-09) — o legado
#    resolvia por **título literal** (`where(title: "Liberação do Recurso")`),
#    de modo que renomear pela tela quebrava a criação de movimentos sem
#    nenhum erro visível até alguém tentar lançar.
class CreateRiskMovementTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_movement_types, id: :uuid, default: -> { 'gen_random_uuid()' },
                                       comment: 'Tipo de movimentação de risco. O credit_type é o SINAL do movimento no recálculo do saldo.' do |t|
      t.string :title, null: false, comment: 'Nome do tipo. Único.'
      t.string :integration_key, null: false,
                                 comment: 'Chave estável. CONTRATO: liberacao_do_recurso, valor_transferido, transferencia_recebida (B-09).'
      t.boolean :is_active, null: false, default: true
      t.uuid :user_id
      t.boolean :is_default, null: false, default: false, comment: 'Linha semeada pelo sistema. Bloqueia a exclusão.'
      t.boolean :is_system_exclusive, null: false, default: false,
                                      comment: 'Só o sistema lança (Liberação do Recurso). Não aparece no formulário manual.'
      t.string :credit_type, null: false, limit: 1,
                             comment: "'C' = crédito (−1 no saldo) · 'D' = débito (+1). Restrito por check — fora disso o movimento não mexeria no saldo, em silêncio."
      t.boolean :is_transfer, null: false, default: false,
                              comment: 'Movimento de transferência entre o par pré/antecipação. Dispara o movimento espelho (S7).'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :risk_movement_types, :title, unique: true
    add_index :risk_movement_types, :integration_key, unique: true
    add_index :risk_movement_types, :legacy_id, unique: true
    add_index :risk_movement_types, :is_active

    add_check_constraint :risk_movement_types, "credit_type IN ('C', 'D')", name: 'risk_movement_types_credit_type_check'

    add_foreign_key :risk_movement_types, :users, column: :user_id
  end
end
