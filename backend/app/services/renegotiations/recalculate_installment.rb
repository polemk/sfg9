# frozen_string_literal: true

module Renegotiations
  # S9 / BE-219, BE-220 — **a cascata pagamento → parcela → renegociação**,
  # escrita, explícita e rodando **uma vez**.
  #
  # No legado ela era feita de callbacks encadeados
  # (`renegotiation_payment.rb:16-22` → `renegotiation_installment.rb:71-76` →
  # `renegotiation.rb:83-86`), e o controller ainda fazia `update` **e** `save`,
  # disparando a corrente duas vezes por operação. Pior: cada elo gravava com
  # `save` sem bang, então uma falha no meio deixava parcela e agregado
  # divergentes **sem erro nenhum** (D-79).
  #
  # Aqui:
  #
  #   renumera pagamentos → recalcula a parcela → recalcula a renegociação
  #
  # tudo dentro de **uma** transação. Falha em qualquer elo reverte a corrente
  # inteira e é reportada. O broadcast sai depois do COMMIT, uma vez.
  class RecalculateInstallment
    class << self
      # `renumber:` existe porque a renumeração de pagamentos só faz sentido
      # quando a coleção mudou. Recalcular a parcela porque o VALOR dela mudou
      # não precisa renumerar nada.
      def call!(installment, renumber: true, broadcast: true)
        renegotiation = installment.renegotiation

        installment.transaction do
          RenumberPayments.call(installment) if renumber

          somas = payment_sums(installment)
          derivados = Formulas.installment(
            main_value: installment.main_value,
            interest_value: installment.interest_value,
            monetary_correction_value: installment.monetary_correction_value,
            late_payment_value: somas[:late_payment_value],
            paid_value: somas[:total_paid_value]
          )

          derivados.each { |campo, valor| installment.public_send(:"#{campo}=", valor) }
          installment.save!

          # A renegociação é recalculada DENTRO da mesma transação, mas o
          # broadcast dela é suprimido: quem avisa é esta classe, uma vez só, e
          # depois do COMMIT.
          AggregateService.recalculate!(renegotiation, broadcast: false)
        end

        RenegotiationChannel.publish_changed(renegotiation) if broadcast
        installment
      end

      # As duas somas que a parcela precisa dos pagamentos, numa consulta.
      #
      # **A mora entra dos dois lados** (Q-B26): `late_payment_value` vai para o
      # DEVIDO da parcela e já está embutida em `total_paid_value`, que vai para o
      # PAGO. No saldo da parcela os dois se cancelam — mas no agregado da
      # renegociação não, porque lá "R$ Pago" conta a mora e "R$ A Pagar" não.
      # Replicado (DEC-02); é o que o golden test 4.10 trava.
      def payment_sums(installment)
        linha = RenegotiationPayment
                .where(renegotiation_installment_id: installment.id)
                .pick(Arel.sql('COALESCE(SUM(late_payment_value), 0), COALESCE(SUM(total_paid_value), 0)'))

        { late_payment_value: linha&.first || 0, total_paid_value: linha&.last || 0 }
      end
    end
  end
end
