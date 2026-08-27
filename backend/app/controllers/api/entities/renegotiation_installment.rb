# frozen_string_literal: true

module Api
  module Entities
    # S9 / BE-213, BE-217 — forma da parcela na API.
    #
    # Os pagamentos vêm **aninhados**, porque a tela os mostra como sublinha da
    # parcela (FE-215) e buscá-los separadamente por linha seria o N+1 que o
    # legado tinha.
    #
    # `batch_token` e `color` são a **identidade do lote** (BE-217): parcelas
    # criadas juntas compartilham os dois, e é assim que a tela as agrupa.
    class RenegotiationInstallment < Grape::Entity
      expose :id
      expose :renegotiation_id
      expose :number, documentation: { desc: 'Ordinal por vencimento (`installment` no legado)' }
      expose :due_date
      expose :month
      expose :year

      expose :main_value, documentation: { desc: 'PRINCIPAL — desde 2022 não é mais o total (DEC-94)' }
      expose :interest_value
      expose :main_value_with_interest
      expose :monetary_correction_value
      expose :main_value_with_interest_cm
      expose :late_payment_value, documentation: { desc: 'Mora somada dos pagamentos. Entra no devido E no pago' }
      expose :installment_total_value
      expose :paid_value
      expose :saldo, documentation: { desc: 'pago - devido. NEGATIVO enquanto falta pagar' }
      expose :pending_value, documentation: { desc: 'devido - pago, com PISO EM ZERO' }
      expose :is_paid

      expose :batch_token
      expose :color

      expose :has_payments do |i|
        i.payments.loaded? ? i.payments.any? : i.payments.exists?
      end
      expose :payments, using: Api::Entities::RenegotiationPayment do |i|
        i.payments.sort_by { |p| [p.created_at, p.id] }
      end

      expose :created_at
      expose :updated_at
    end
  end
end
