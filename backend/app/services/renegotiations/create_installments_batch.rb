# frozen_string_literal: true

module Renegotiations
  # S9 / BE-215, BE-216, BE-217 — **criação de parcela: única ou em lote**.
  #
  # Substitui `RenegotiationInstallment.create_batch_installments`
  # (`renegotiation_installment.rb:116-252`), que tem 137 linhas com os dois ramos
  # (única e múltipla) **copiados um do outro**. Quatro defeitos morrem aqui:
  #
  # 1. **Duplicata DENTRO do próprio lote falhava em silêncio** (D-52). O legado
  #    conferia sobreposição só contra as parcelas **já existentes**; se o lote
  #    trouxesse duas vezes a mesma data, a primeira era criada, a segunda falhava
  #    na validação, o retorno de `create` era **ignorado**, e a resposta era
  #    `success = true` — "criadas com sucesso", com uma parcela a menos.
  # 2. **`repetitions` não numérico virava 0.** `params[...].to_i` transformava
  #    `"abc"` em 0, o laço `[*0..-1]` ficava vazio, nada era criado e a resposta
  #    era 200. Aqui é **422** (BE-214).
  # 3. **Intervalo 0 gerava N parcelas na MESMA data**, todas menos a primeira
  #    inválidas — e a resposta continuava de sucesso. Aqui é 422.
  # 4. **Tipo de intervalo desconhecido** deixava `date` sem atribuição e
  #    levantava `NameError` dentro do laço. Aqui é 422 com o nome do que é aceito.
  #
  # **Ajuste de fim de mês:** o intervalo em meses usa `>>`, o mesmo operador do
  # `+ n.months` do legado — 31/01 + 1 mês é 28/02 (ou 29/02), não 03/03.
  class CreateInstallmentsBatch
    MAX_REPETITIONS = 360

    class << self
      include Result

      # `attrs`:
      #   due_date (Date/String)  — data da primeira parcela (ou da única)
      #   main_value, interest_value, monetary_correction_value
      #   multiple (bool), repetitions (Integer), repetition_delay (Integer),
      #   repetition_type ('Dias' | 'Semanas' | 'Meses')
      def call(renegotiation:, attrs:)
        datas = build_dates(attrs)
        return datas if datas.is_a?(Hash) # erro já formatado

        sobrepostas = overlapping(renegotiation, datas)
        if sobrepostas.any?
          return unprocessable(
            "Parcelas sobrepostas à parcelas já existentes: #{sobrepostas.map { |d| d.strftime('%d/%m/%Y') }
              .join(', ')}"
          )
        end

        criar!(renegotiation, datas, attrs)
      rescue ActiveRecord::RecordInvalid => e
        from_record_invalid(e)
      rescue ActiveRecord::RecordNotUnique
        # O índice único do banco batendo antes da validação (duas abas).
        unprocessable('Já existe parcela com um destes vencimentos nesta renegociação.')
      end

      # **Público de propósito.** A prévia da tela chama exatamente esta função
      # para saber QUAIS datas o lote produziria — se ela fosse privada, o
      # endpoint de prévia teria de recalcular as datas por conta própria, e o
      # contrato C2 estaria quebrado no primeiro fim de mês.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def build_dates(attrs)
        inicio = parse_date(attrs[:due_date])
        return unprocessable('Informe a data da parcela.') if inicio.nil?

        return [inicio] unless truthy?(attrs[:multiple])

        repeticoes = attrs[:repetitions]
        # **Não numérico é 422, não 0.** Este é o `to_i` do legado.
        unless numeric?(repeticoes)
          return unprocessable('A quantidade de parcelas precisa ser um número.')
        end

        repeticoes = repeticoes.to_i
        if repeticoes < 1
          return unprocessable('A quantidade de parcelas precisa ser pelo menos 1.')
        end
        if repeticoes > MAX_REPETITIONS
          return unprocessable("A quantidade de parcelas não pode passar de #{MAX_REPETITIONS}.")
        end

        intervalo = attrs[:repetition_delay]
        unless numeric?(intervalo)
          return unprocessable('O intervalo entre as parcelas precisa ser um número.')
        end

        intervalo = intervalo.to_i
        # Intervalo 0 com mais de uma parcela = N parcelas na mesma data.
        if intervalo < 1 && repeticoes > 1
          return unprocessable('O intervalo entre as parcelas precisa ser maior que zero.')
        end

        tipo = attrs[:repetition_type].to_s
        unless RenegotiationInstallment::DELAY_TYPES.include?(tipo)
          return unprocessable(
            "Tipo de intervalo desconhecido. Use: #{RenegotiationInstallment::DELAY_TYPES.join(', ')}."
          )
        end

        datas = (0...repeticoes).map { |i| avancar(inicio, i * intervalo, tipo) }
        duplicadas = datas.tally.select { |_, n| n > 1 }.keys
        if duplicadas.any?
          return unprocessable(
            'O lote gerou vencimentos repetidos. Ajuste o intervalo ou a quantidade de parcelas.'
          )
        end

        datas
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      def avancar(data, passo, tipo)
        case tipo
        when RenegotiationInstallment::DELAY_DAY then data + passo
        when RenegotiationInstallment::DELAY_WEEK then data + (passo * 7)
        # `>>` é o avanço de meses do Ruby: 31/01 >> 1 é 28/02, igual ao `.months`.
        when RenegotiationInstallment::DELAY_MONTH then data >> passo
        end
      end

      def overlapping(renegotiation, datas)
        RenegotiationInstallment
          .where(renegotiation_id: renegotiation.id, due_date: datas)
          .pluck(:due_date)
          .sort
      end

      def criar!(renegotiation, datas, attrs)
        # **Identidade do lote**: as parcelas criadas juntas compartilham token e
        # cor, e é isso que a tela usa para agrupá-las (BE-217).
        token = SecureRandom.uuid
        cor = BatchColor.next_for(renegotiation.id)
        criadas = []

        RenegotiationInstallment.transaction do
          datas.each do |data|
            derivados = Formulas.installment(
              main_value: attrs[:main_value],
              interest_value: attrs[:interest_value],
              monetary_correction_value: attrs[:monetary_correction_value]
            )

            # `create!`, com bang: o retorno do `create` do legado era ignorado, e
            # é daí que vinha o "criadas com sucesso" sem ter criado.
            criadas << RenegotiationInstallment.create!(
              renegotiation: renegotiation,
              project_id: renegotiation.project_id,
              due_date: data,
              main_value: Formulas.dec(attrs[:main_value]),
              interest_value: Formulas.dec(attrs[:interest_value]),
              monetary_correction_value: Formulas.dec(attrs[:monetary_correction_value]),
              batch_token: token,
              color: cor,
              **derivados
            )
          end

          RenumberInstallments.call(renegotiation)
          AggregateService.recalculate!(renegotiation, broadcast: false)
        end

        RenegotiationChannel.publish_changed(renegotiation)
        created({ created: criadas.size, batch_token: token,
                  installments: criadas.map(&:reload) })
      end

      def parse_date(valor)
        return valor if valor.is_a?(Date)
        return valor.to_date if valor.respond_to?(:to_date) && !valor.is_a?(String)

        Date.parse(valor.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def numeric?(valor)
        return true if valor.is_a?(Numeric)

        valor.to_s.strip.match?(/\A-?\d+\z/)
      end

      def truthy?(valor)
        ActiveModel::Type::Boolean.new.cast(valor) == true
      end
    end
  end
end
