# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `renegotiation_payments` (legado) -> `RenegotiationPayment`. **S9 / DB-194.**
      #
      # O terceiro renomeado de 29/04/2022 é aqui: `value ->
      # installment_paid_value_with_interest_cm` (DEC-94). A origem já vem com o
      # nome novo.
      #
      # ## O que este conversor tem de conferir e o legado nunca conferiu
      #
      # **A coerência renegociação × parcela** (D-52). No legado os dois ids eram
      # inteiros soltos, vindos do `permit`, e nenhum era conferido contra o outro:
      # é razoável esperar linhas de produção em que `renegotiation_id` não bate
      # com o da parcela. No ai9 isso é **FK composta** — a linha incoerente
      # simplesmente não entra. Por isso ela é reportada como anomalia **antes**,
      # no dry-run: o conserto é decisão do cliente (qual dos dois ids está certo),
      # não do ETL.
      class RenegotiationPayments < Base
        def self.source_table = 'renegotiation_payments'
        def self.target_model = 'RenegotiationPayment'
        def self.requires = %w[RenegotiationPayment RenegotiationInstallment Renegotiation]
        def self.owner_slice = 'S9'

        def self.references = {
          'renegotiation_id' => 'renegotiations',
          'renegotiation_installment_id' => 'renegotiation_installments'
        }

        def self.uniques = []
        def self.sums = %w[installment_paid_value_with_interest_cm late_payment_value total_paid_value]
        def self.year_column = 'date'

        def convert(row)
          installment_id = ref('renegotiation_installments', row['renegotiation_installment_id'])
          # **A renegociação vem da PARCELA, não da coluna da origem.** É o único
          # jeito de a linha entrar quando os dois ids do legado divergem — e é a
          # escolha certa porque o pagamento pertence à parcela; a renegociação é
          # consequência. A divergência continua reportada em `anomalies`.
          parcela = installment_id && ::RenegotiationInstallment.where(id: installment_id)
                                                                .pick(:renegotiation_id, :project_id)

          {
            renegotiation_installment_id: installment_id,
            renegotiation_id: parcela&.first,
            project_id: parcela&.last,

            payment_number: row['payment_number']&.to_i,
            date: row['date'],
            days_late: row['days_late'].to_i,

            installment_paid_value_with_interest_cm:
              Values.to_decimal(row['installment_paid_value_with_interest_cm']),
            late_payment_value: Values.to_decimal(row['late_payment_value']),
            total_paid_value: Values.to_decimal(row['total_paid_value']),

            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          achados = []
          parcela_id = ref('renegotiation_installments', row['renegotiation_installment_id'])
          reneg_da_origem = ref('renegotiations', row['renegotiation_id'])
          reneg_da_parcela = parcela_id && ::RenegotiationInstallment.where(id: parcela_id).pick(:renegotiation_id)

          if reneg_da_parcela.present? && reneg_da_origem.present? && reneg_da_parcela != reneg_da_origem
            achados << "payment ##{row['id']}: renegotiation_id DIVERGE do da parcela (D-52). " \
                       'A carga adota o da parcela; confira qual está certo.'
          end
          if row['installment_paid_value_with_interest_cm'].to_d <= 0
            achados << "payment ##{row['id']}: valor pago <= 0 — a CHECK do ai9 recusa"
          end
          achados << "payment ##{row['id']}: mora NEGATIVA" if row['late_payment_value'].to_d.negative?
          achados
        end
      end
    end
  end
end
