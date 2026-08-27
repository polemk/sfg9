# frozen_string_literal: true

# S9 / DB-192, DB-198, DB-570 — **pagamentos de uma parcela**.
#
# **A coerência renegociação × parcela é garantida NO BANCO** — é a raiz do
# **D-52**. No legado o pagamento tinha `renegotiation_id` e
# `renegotiation_installment_id` como dois inteiros soltos, os dois vindos do
# `permit` do formulário e nenhum conferido contra o outro: trocar o
# `renegotiation_id` num campo escondido lançava o pagamento numa renegociação e o
# recálculo noutra, e as duas ficavam erradas. Aqui a FK é **composta** —
# `(renegotiation_installment_id, renegotiation_id) → renegotiation_installments
# (id, renegotiation_id)` —, então o par incoerente **não entra na tabela**, venha
# de onde vier. O serviço confere antes para dar erro legível; o banco confere
# depois porque serviço se contorna.
#
# `project_id` é denormalizado pelo mesmo motivo das parcelas (reset por projeto e
# checagem C1 direta) e é coerente com a parcela pela mesma técnica.
#
# **O que este pagamento NÃO tem, e é ausência preservada** (Q-B30): forma de
# pagamento e conciliação bancária. O legado não registra nenhuma das duas, e
# inventá-las aqui seria pedir ao operador um dado que ninguém definiu.
class CreateRenegotiationPayments < ActiveRecord::Migration[8.0]
  def change
    create_table :renegotiation_payments, id: :uuid, default: -> { 'gen_random_uuid()' },
                                          comment: 'Pagamento lançado contra UMA parcela de renegociação.' do |t|
      t.uuid :renegotiation_installment_id, null: false, comment: 'Parcela paga.'
      t.uuid :renegotiation_id, null: false,
                                comment: 'Renegociação, coerente com a da parcela por FK COMPOSTA (corrige D-52).'
      t.uuid :project_id, null: false, comment: 'Projeto, denormalizado e coerente por FK composta (C1).'

      t.integer :payment_number, comment: 'Ordinal do pagamento dentro da parcela, renumerado por data de criação.'
      t.date :date, null: false,
                    comment: 'Data do pagamento. **EDITÁVEL** (D-B12): no legado o campo era travado em "hoje", ' \
                             'o que tornava `days_late` sempre 0 e impedia lançamento retroativo.'
      t.integer :days_late, null: false, default: 0,
                            comment: 'Dias de atraso = data - vencimento da parcela, com piso em 0.'

      t.decimal :installment_paid_value_with_interest_cm, precision: 15, scale: 2, null: false, default: 0,
                                                          comment: 'Pago referente a principal+juros+CM. Obrigatório > 0. ' \
                                                                   'Renomeada de `value` em 29/04/2022 (DEC-94).'
      t.decimal :late_payment_value, precision: 15, scale: 2, null: false, default: 0,
                                     comment: 'Mora paga. Nunca negativa.'
      t.decimal :total_paid_value, precision: 15, scale: 2, null: false, default: 0,
                                   comment: 'Total = pago sem mora + mora. Derivado, nunca digitado.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :renegotiation_payments, :renegotiation_installment_id, name: 'index_reneg_payments_on_installment'
    add_index :renegotiation_payments, :renegotiation_id, name: 'index_reneg_payments_on_renegotiation'
    add_index :renegotiation_payments, :project_id, name: 'index_reneg_payments_on_project'
    # Ordem DETERMINÍSTICA da listagem (BE-222): o legado não tinha `ORDER BY`
    # nenhum e a ordem dependia do plano do banco.
    add_index :renegotiation_payments, %i[renegotiation_installment_id created_at],
              name: 'index_reneg_payments_ordering'
    add_index :renegotiation_payments, :date, name: 'index_reneg_payments_on_date'
    add_index :renegotiation_payments, :legacy_id, unique: true, name: 'index_reneg_payments_on_legacy_id'

    add_foreign_key :renegotiation_payments, :projects, column: :project_id
    add_foreign_key :renegotiation_payments, :renegotiation_installments,
                    column: %i[renegotiation_installment_id renegotiation_id],
                    primary_key: %i[id renegotiation_id],
                    name: 'fk_reneg_payments_installment_renegotiation'
    add_foreign_key :renegotiation_payments, :renegotiations,
                    column: %i[renegotiation_id project_id],
                    primary_key: %i[id project_id],
                    name: 'fk_reneg_payments_renegotiation_project'

    add_check_constraint :renegotiation_payments, 'installment_paid_value_with_interest_cm > 0',
                         name: 'reneg_payments_value_positive'
    add_check_constraint :renegotiation_payments, 'late_payment_value >= 0',
                         name: 'reneg_payments_late_non_negative'
    add_check_constraint :renegotiation_payments, 'days_late >= 0',
                         name: 'reneg_payments_days_late_non_negative'
  end
end
