# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `renegotiation_installments` (legado) -> `RenegotiationInstallment`. **S9 / DB-194.**
      #
      # ## Duas renomeações, e uma delas muda o significado (DEC-94 / Q-B31)
      #
      # `value -> main_value`, em 29/04/2022. **O valor da parcela passou a ser só
      # o principal**: antes a coluna era o total. A origem já vem com o nome novo.
      #
      # ## O que este conversor mapeia e o legado não tem
      #
      # - **`number`** ← `installment`. O ordinal foi renomeado (ver a migration
      #   `20260826190100`): `renegotiation_installments.installment` é uma coluna
      #   que se nomeia a si mesma, e o escritor do seed de demonstração já grava
      #   `number`. Nenhum conversor é cópia cega — todo id inteiro do legado vira
      #   uuid aqui —, então a renomeação não custa nada.
      # - **`project_id`** ← denormalizado da renegociação, e garantido coerente
      #   pela FK COMPOSTA. O legado não tem a coluna: ela é resolvida pelo de-para
      #   do PAI, não pelo da parcela.
      # - **`batch_token`** ← na origem é `string`; no ai9 é `uuid` e `null: false`.
      #   Linha sem token (ou com token que não é uuid) recebe um novo, e o fato é
      #   reportado: o token é identidade de LOTE, e inventar um por linha
      #   desagrupa o lote — o que é melhor do que recusar a carga do registro.
      class RenegotiationInstallments < Base
        def self.source_table = 'renegotiation_installments'
        def self.target_model = 'RenegotiationInstallment'
        def self.requires = %w[RenegotiationInstallment Renegotiation]
        def self.owner_slice = 'S9'

        def self.references = { 'renegotiation_id' => 'renegotiations' }

        # `is_paid` é `integer` 0/1 no legado e boolean no ai9.
        def self.booleans = %w[is_paid]

        def self.uniques = [%w[renegotiation_id due_date]]

        def self.sums = %w[main_value installment_total_value paid_value pending_value saldo]
        def self.year_column = 'due_date'

        UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

        def convert(row)
          renegotiation_id = ref('renegotiations', row['renegotiation_id'])

          {
            renegotiation_id: renegotiation_id,
            # O projeto vem do PAI já migrado — nunca de uma coluna da origem, que
            # não existe. Se o pai for órfão, a linha é contada como órfã e não
            # entra: a FK composta recusaria de qualquer forma.
            project_id: renegotiation_id && ::Renegotiation.where(id: renegotiation_id).pick(:project_id),

            number: row['installment']&.to_i,
            due_date: row['due_date'],
            month: row['month']&.to_i,
            year: row['year']&.to_i,

            main_value: Values.to_decimal(row['main_value']),
            interest_value: Values.to_decimal(row['interest_value']),
            main_value_with_interest: Values.to_decimal(row['main_value_with_interest']),
            monetary_correction_value: Values.to_decimal(row['monetary_correction_value']),
            main_value_with_interest_cm: Values.to_decimal(row['main_value_with_interest_cm']),
            late_payment_value: Values.to_decimal(row['late_payment_value']),
            installment_total_value: Values.to_decimal(row['installment_total_value']),
            paid_value: Values.to_decimal(row['paid_value']),
            saldo: Values.to_decimal(row['saldo']),
            pending_value: Values.to_decimal(row['pending_value']),
            is_paid: row['is_paid'],

            batch_token: normalizar_token(row['batch_token']),
            color: normalizar_cor(row['color']),

            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          achados = []
          if row['batch_token'].blank? || !row['batch_token'].to_s.match?(UUID)
            achados << "installment ##{row['id']}: batch_token ausente ou fora do formato uuid — " \
                       'o lote perde o agrupamento na tela'
          end
          if row['main_value'].to_d <= 0
            # O ai9 exige `main_value > 0` no banco (CHECK). Linha assim NÃO entra —
            # e é melhor saber disso no dry-run do que na janela de cutover.
            achados << "installment ##{row['id']}: main_value <= 0 — a CHECK do ai9 recusa"
          end
          achados
        end

        private

        def normalizar_token(valor)
          valor.to_s.match?(UUID) ? valor : SecureRandom.uuid
        end

        # A coluna do ai9 é `limit: 9`. A do legado é `string` livre.
        def normalizar_cor(valor)
          cor = valor.to_s.strip
          cor.match?(/\A#\h{3,8}\z/) ? cor[0, 9] : nil
        end
      end
    end
  end
end
