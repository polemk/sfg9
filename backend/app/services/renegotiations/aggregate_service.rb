# frozen_string_literal: true

module Renegotiations
  # S9 / BE-195, BE-204..BE-212, OPS-190 — **o cálculo único** (contrato C2).
  #
  # Todo caminho que muda parcela ou pagamento termina aqui, e **só** aqui os ~20
  # agregados da renegociação são escritos. A pré-visualização da tela chama as
  # **mesmas** fórmulas (`Renegotiations::Formulas`) sem persistir — é o que
  # garante que a simulação e o salvamento produzam o mesmo número.
  #
  # Três defeitos do legado morrem neste arquivo:
  #
  # - **D-79** — `Renegotiation#update_values!` (`renegotiation.rb:83-86`) fazia
  #   `save` **sem bang**: uma falha de validação descartava o recálculo **em
  #   silêncio**, e agregado e parcela divergiam sem ninguém saber. Aqui é
  #   `save!` dentro de transação: a falha **levanta** e é revertida.
  # - **D-54** — `overdue_installments` era coluna atualizada por **cron diário**,
  #   até 24 h desatualizada, e a renegociação liquidada nunca mais era
  #   reprocessada. A fórmula não muda; o que muda é que ela roda em toda
  #   alteração e a leitura a apura na consulta (`#live_overdue_for`).
  # - **A cascata em duplicidade** — o `after_save` do pagamento chamava a
  #   parcela, que chamava a renegociação, e o controller ainda fazia `update` +
  #   `save`. Aqui a cascata é escrita, explícita, e roda **uma vez**.
  #
  # **`recalculate!` não é idempotente por acaso: é idempotente por construção.**
  # Ela deriva tudo do estado atual das parcelas e dos pagamentos; chamá-la duas
  # vezes seguidas produz o mesmo resultado. É o que permite o teste de "cascata
  # única" contar chamadas sem medo de mascarar erro.
  class AggregateService
    # Colunas que uma parcela precisa expor para as fórmulas. Uma lista só, usada
    # pelo carregamento e pelo desenho da prévia — se divergirem, a prévia e a
    # gravação passam a ver conjuntos diferentes, que é o C2 quebrado.
    INSTALLMENT_FIELDS = %i[
      id due_date month year is_paid
      main_value interest_value monetary_correction_value
      main_value_with_interest main_value_with_interest_cm
      late_payment_value installment_total_value paid_value saldo pending_value
    ].freeze

    # Os agregados que a renegociação persiste. Explícito para que acrescentar um
    # campo às fórmulas sem acrescentá-lo aqui seja um erro visível, e não um
    # número que some da tela.
    PERSISTED_FIELDS = %i[
      installments_count first_due_date last_due_date correct_value
      installments_main_value installments_interest_value
      installments_main_value_with_interest installments_monetary_correction_value
      installments_main_value_with_interest_cm main_value
      paid_value_with_interest_cm pending_main_value paid_percent
      late_payment_value paid_value remaining_value
      paid_installments overdue_installments due_installments
      total_value_with_desagio state
      current_installment_value current_value
    ].freeze

    class << self
      # Recalcula e **PERSISTE**. Levanta em falha — nunca `save` sem bang.
      # Devolve a renegociação recarregada.
      def recalculate!(renegotiation, today: Date.current, broadcast: true)
        valores = compute(renegotiation, today: today)

        renegotiation.transaction do
          PERSISTED_FIELDS.each { |campo| renegotiation.public_send(:"#{campo}=", valores[campo]) }
          renegotiation.save!
        end

        # **Depois** da transação: um broadcast emitido dentro dela chegaria ao
        # assinante antes do COMMIT, e a tela leria o estado anterior (D-B5).
        RenegotiationChannel.publish_changed(renegotiation) if broadcast
        renegotiation
      end

      # Mesmas fórmulas, **sem persistir**. É o que a prévia da tela consome
      # (FE-221 / C2).
      #
      # `draft_installments` são parcelas que ainda não existem (o que o painel
      # está montando); `replacing_id` retira do cálculo a parcela que está sendo
      # editada, para que a prévia mostre o resultado da EDIÇÃO e não a soma da
      # versão velha com a nova.
      def preview(renegotiation, draft_installments: [], replacing_id: nil, today: Date.current)
        atuais = load_installments(renegotiation)
        atuais = atuais.reject { |i| i[:id].to_s == replacing_id.to_s } if replacing_id.present?

        rascunhos = Array(draft_installments).map { |d| draft_installment(d) }

        compute_from(renegotiation, atuais + rascunhos, load_payments(renegotiation), today: today)
          .merge(preview_installments: rascunhos)
      end

      # Deriva UMA parcela a partir do que o usuário digitou. É a **mesma** função
      # que a gravação usa (`CreateInstallment`), e é isso que faz o teste 4.13
      # (prévia × gravação, campo a campo) ser possível.
      def draft_installment(attrs)
        attrs = attrs.symbolize_keys
        vencimento = attrs[:due_date].is_a?(Date) ? attrs[:due_date] : Date.parse(attrs[:due_date].to_s)

        derivados = Formulas.installment(
          main_value: attrs[:main_value],
          interest_value: attrs[:interest_value],
          monetary_correction_value: attrs[:monetary_correction_value]
        )

        {
          id: nil,
          due_date: vencimento,
          month: vencimento.month,
          year: vencimento.year,
          main_value: Formulas.dec(attrs[:main_value]),
          interest_value: Formulas.dec(attrs[:interest_value]),
          monetary_correction_value: Formulas.dec(attrs[:monetary_correction_value])
        }.merge(derivados)
      end

      # Só calcula — nem persiste nem toca no registro.
      def compute(renegotiation, today: Date.current)
        compute_from(renegotiation, load_installments(renegotiation), load_payments(renegotiation), today: today)
      end

      # **Vencidas apuradas na CONSULTA** (OPS-190). Recebe um escopo de
      # renegociações e devolve `{ renegotiation_id => contagem }`, numa consulta
      # só — é o que substitui o cron diário sem transformar a listagem em N+1.
      def live_overdue_for(scope, today: Date.current)
        RenegotiationInstallment
          .where(renegotiation_id: scope.select(:id))
          .overdue(today)
          .group(:renegotiation_id)
          .count
      end

      # **Quantas RENEGOCIAÇÕES estão em atraso** — não quantas parcelas.
      #
      # S15 / NEW-002. Reusa `live_overdue_for` (a mesma apuração na consulta que
      # a listagem já usa, OPS-473/BE-207) e só conta as chaves com pelo menos
      # uma parcela vencida. Nenhuma regra de "o que é atraso" nasce aqui: ela
      # continua sendo o escopo `overdue` da parcela, num lugar só.
      #
      # Dono: **S9/S13**. Consumidor: S15.
      def overdue_renegotiations_count(scope, today: Date.current)
        live_overdue_for(scope, today: today).count { |_id, qtd| qtd.to_i.positive? }
      end

      # **QUAIS renegociações estão em atraso** — a lista, não a contagem.
      #
      # S15 / painel. O cartão "Renegociações em atraso" diz **quantas**; isto diz
      # **quais**, e com quantas parcelas cada uma — é o mesmo par que a DEC-116
      # estabeleceu para os limites, pela mesma razão: saber que há atraso e
      # saber onde ele está são decisões diferentes.
      #
      # Reusa `live_overdue_for` (a apuração na consulta, OPS-473/BE-207) e só
      # carrega os registros das chaves que sobraram. Nenhuma regra de "o que é
      # atraso" nasce aqui: ela continua sendo o escopo `overdue` da parcela.
      #
      # `total_debt` é **lido da coluna**, como a tela de detalhe faz — é o
      # agregado que `recalculate!` mantém, não uma soma feita aqui.
      #
      # Dono: **S9/S13**. Consumidor: S15.
      def overdue_renegotiations_on(scope, today: Date.current, limit: nil)
        vencidas = live_overdue_for(scope, today: today).select { |_id, qtd| qtd.to_i.positive? }
        return [] if vencidas.empty?

        registros = ::Renegotiation.where(id: vencidas.keys).index_by(&:id)

        linhas = vencidas.filter_map do |id, qtd|
          reneg = registros[id]
          next if reneg.nil?

          {
            id: reneg.id,
            title: reneg.title.to_s,
            provider_name: reneg.provider_name.to_s,
            kind: reneg.kind.to_s,
            overdue_count: qtd.to_i,
            total_debt: reneg.total_debt
          }
        end

        # Mais parcelas vencidas primeiro; empate pelo título, para a ordem não
        # variar entre chamadas.
        ordenadas = linhas.sort_by { |linha| [-linha[:overdue_count], linha[:title]] }
        limit ? ordenadas.first(limit) : ordenadas
      end

      private

      def compute_from(renegotiation, parcelas, pagamentos, today:)
        Formulas.aggregate(
          installments: parcelas,
          payments: pagamentos,
          total_debt: renegotiation.total_debt,
          original_value: renegotiation.original_value,
          desagio_value: renegotiation.desagio_value,
          operation_interest_rate: renegotiation.operation_interest_rate,
          today: today
        )
      end

      # Uma consulta, não dez `pluck` como o legado.
      def load_installments(renegotiation)
        return [] if renegotiation.new_record?

        RenegotiationInstallment
          .where(renegotiation_id: renegotiation.id)
          .pluck(*INSTALLMENT_FIELDS)
          .map { |linha| INSTALLMENT_FIELDS.zip(linha).to_h }
      end

      def load_payments(renegotiation)
        return [] if renegotiation.new_record?

        RenegotiationPayment
          .where(renegotiation_id: renegotiation.id)
          .pluck(:installment_paid_value_with_interest_cm)
          .map { |v| { installment_paid_value_with_interest_cm: v } }
      end
    end
  end
end
