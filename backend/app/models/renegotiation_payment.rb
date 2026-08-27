# frozen_string_literal: true

# S9 / BE-223, DB-192 — **pagamento lançado contra uma parcela**.
#
# Duas derivações vêm do legado (`renegotiation_payment.rb:11-14`) e ficam aqui
# porque são propriedades **do próprio registro**, não agregação de outros:
#
#   days_late        = data - vencimento da parcela, com piso em 0
#   total_paid_value = pago sem mora + mora
#
# O que **não** fica aqui é o `after_save` que chamava
# `renegotiation_installment.update_values!`. Ele, combinado com o `update` +
# `save` redundante do controller do legado, disparava a cascata em duplicidade.
# A cascata agora é explícita e transacional (`Renegotiations::PaymentService`).
class RenegotiationPayment < ApplicationRecord
  include ProjectScoped

  belongs_to :renegotiation_installment, inverse_of: :payments
  belongs_to :renegotiation, inverse_of: :payments

  validates :date, presence: true
  validates :installment_paid_value_with_interest_cm, presence: true, numericality: { greater_than: 0 }
  # Mora **nunca negativa**: no legado não havia checagem alguma e um valor
  # negativo reduzia o devido da parcela pelos dois lados da conta.
  validates :late_payment_value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_paid_value, presence: true, numericality: { greater_than: 0 }
  validates :renegotiation_installment_id, :renegotiation_id, presence: true

  # Coerência parcela × renegociação. O banco já a garante (FK composta, D-52 na
  # raiz); esta validação existe para que o usuário receba **422 com motivo** em
  # vez de um erro de integridade do Postgres.
  validate :parcela_pertence_a_renegociacao

  before_validation :derivar_valores

  scope :ordered, -> { order(created_at: :asc, id: :asc) }

  private

  def derivar_valores
    self.project_id ||= renegotiation&.project_id || renegotiation_installment&.project_id
    self.late_payment_value ||= 0

    vencimento = renegotiation_installment&.due_date
    self.days_late = if date.present? && vencimento.present? && date > vencimento
                       (date - vencimento).to_i
                     else
                       0
                     end

    self.total_paid_value = installment_paid_value_with_interest_cm.to_d + late_payment_value.to_d
  end

  def parcela_pertence_a_renegociacao
    return if renegotiation_installment.blank? || renegotiation_id.blank?
    return if renegotiation_installment.renegotiation_id == renegotiation_id

    errors.add(:renegotiation_installment_id, 'não pertence a esta renegociação')
  end
end
