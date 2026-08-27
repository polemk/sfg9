# frozen_string_literal: true

module Renegotiations
  # S9 / BE-220, OPS-195 — **renumeração dos pagamentos de uma parcela**.
  #
  # Mesma regra da renumeração de parcelas: `update_all`, **sem callbacks**. Aqui
  # o motivo é ainda mais direto — no legado `update_payment_numbers!` era chamado
  # de dentro de `RenegotiationInstallment#update_values!`, que por sua vez era
  # chamado pelo `after_save` do pagamento. Renumerar com callbacks ligados
  # reentrava no próprio recálculo que a estava chamando.
  #
  # A ordem é a de **criação** (`created_at`), como no legado — não a da data do
  # pagamento. Com data editável (D-B12) as duas ordens podem divergir; manter a
  # de criação preserva o número que o operador já viu na tela.
  class RenumberPayments
    def self.call(installment)
      ids = RenegotiationPayment
            .where(renegotiation_installment_id: installment.id)
            .order(created_at: :asc, id: :asc)
            .pluck(:id)
      return 0 if ids.empty?

      RenumberInstallments.aplicar(RenegotiationPayment.where(id: ids), ids, coluna: :payment_number)
    end
  end
end
