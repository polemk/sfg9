# frozen_string_literal: true

module Api
  module Entities
    # S9 / BE-222..BE-224 — forma do pagamento na API.
    #
    # ⚠ **DEC-53:** o backend do pagamento é portado; a **aba PAGAMENTOS não tem
    # tela** (espelha o legado, onde ela está comentada). O pagamento aparece na
    # interface pela sublinha da parcela (FE-227).
    class RenegotiationPayment < Grape::Entity
      expose :id
      expose :renegotiation_id
      expose :renegotiation_installment_id
      expose :payment_number
      expose :date, documentation: { desc: 'EDITÁVEL (D-B12): no legado era travada em "hoje"' }
      expose :days_late, documentation: { desc: 'data - vencimento, com piso em 0' }
      expose :installment_paid_value_with_interest_cm
      expose :late_payment_value
      expose :total_paid_value, documentation: { desc: 'pago sem mora + mora — derivado, nunca digitado' }
      expose :created_at
      expose :updated_at
    end
  end
end
