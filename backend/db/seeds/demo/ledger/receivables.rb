# frozen_string_literal: true

module Demo
  class Ledger
    # Os **borderôs** de desconto (`receivable_entries`).
    #
    # É o agregado mais numeroso (~2.900) e o que justifica busca, filtro e
    # paginação existirem na tela. Lista de 6 linhas com paginador vazio parece
    # protótipo (§3, princípio 7).
    #
    # As três identidades que **não podem** ser sorteadas separadamente:
    #   `vlr_bruto_final = valor_bruto − vlr_bruto_recusado`
    #   `qtd_final       = qtd_titulos − qtd_recusada`
    #   `diferenca_float = float_calculado − float_acordado`
    # Um terceiro sorteio em qualquer uma delas é um rodapé que não fecha.
    module Receivables
      # Catálogos globais — são de `OPS-540` (S3). O razão os referencia **por
      # título**, e os títulos abaixo são **os do seed de referência**, copiados
      # de lá letra por letra.
      #
      # Isso já custou os 2.706 borderôs uma vez: o razão dizia
      # `Cartão de crédito` e `Retenção`, e o catálogo entregue diz `Cartão` e
      # não tem `Retenção` (tem `Comissaria`). O `find` devolvia `nil`, o model
      # recusava por `receivable_kind_id` em branco e o escritor inteiro caía.
      # Título que não resolve agora **estoura no escritor**, com o nome do que
      # faltou — em vez de virar coluna nula.
      WALLETS = ['Desconto', 'Antecipação', 'Fomento', 'Conta Garantida', 'ACC'].freeze
      RECEIVABLE_KINDS = %w[Duplicata Cheque Cartão ACC PAC].freeze
      RESOURCE_SOURCES = %w[Caixa Fomento Garantia Recompra Comissaria].freeze

      # Valor médio de um título, por porte do cliente. É o que define a
      # quantidade de títulos do borderô — e a quantidade é o que faz a tela de
      # detalhe parecer real.
      TICKET_RANGE = {
        grande: [18_000.0, 62_000.0],
        medio: [9_000.0, 31_000.0],
        pequeno: [3_400.0, 14_000.0],
        recuperacao: [6_200.0, 22_000.0],
        entrante: [2_800.0, 9_800.0]
      }.freeze

      module_function

      def build(clients, controls, months, base_date, rng)
        by_client = controls.group_by { |c| c.client.slug }
        counters = Hash.new(0)
        borderos = []

        clients.each do |client|
          eligible = by_client.fetch(client.slug, []).select do |control|
            Cast::RECEIVABLE_MODALITIES.include?(control.modality)
          end
          next if eligible.empty?

          months.each do |month|
            next unless Timeline.active?(client, month)

            stream = rng.keyed(:receivables, client.slug, month.offset)
            available = eligible.select { |c| c.carrier.available_from <= month.offset }
            next if available.empty?

            borderos.concat(
              month_batch(client, available, month, base_date, counters, stream)
            )
          end
        end

        borderos
      end

      def month_batch(client, available, month, base_date, counters, stream)
        min_count, max_count = Cast::BORDEROS_PER_MONTH.fetch(client.tier)
        count = stream.int(min_count, max_count)
        target = client.base_volume * month.factor * Timeline.client_modifier(client, month)

        weights = Array.new(count) { stream.tailed(0.4, 3.0) }
        total_weight = weights.sum

        Array.new(count) do |i|
          control = available[stream.int(0, available.length - 1)]
          gross = target * weights[i] / total_weight
          counters[client.slug] += 1
          build_bordero(client, control, month, base_date, counters[client.slug], gross, stream)
        end
      end

      def build_bordero(client, control, month, base_date, sequence, gross, stream)
        date = day_in_month(month, base_date, stream)
        valor_bruto = Support::Money.natural(gross, stream)

        min_ticket, max_ticket = TICKET_RANGE.fetch(client.tier)
        avg_ticket = stream.float(min_ticket, max_ticket)
        qtd_titulos = [(valor_bruto / avg_ticket).round, 1].max

        qtd_recusada, vlr_recusado = refusal(control.carrier, qtd_titulos, valor_bruto, stream)
        qtd_final = qtd_titulos - qtd_recusada
        vlr_bruto_final = Support::Money.round2(valor_bruto - vlr_recusado)

        prz_emp = stream.int(26, 68)
        prz_bco = prz_emp + stream.int(0, 4)
        float_acordado = stream.int(1, 3)
        float_calculado = [float_acordado + stream.int(-1, 2), 0].max

        nominal_tax = (control.taxa + stream.float(-0.09, 0.09)).round(4)
        desagio = Support::Money.monthly_interest(vlr_bruto_final, nominal_tax, prz_bco)
        advalorem = Support::Money.round2(vlr_bruto_final * stream.float(0.003, 0.005))
        iof = Support::Money.iof(vlr_bruto_final, prz_emp)
        outras = Support::Money.round2((qtd_final * stream.float(2.9, 8.5)) + stream.float(35.0, 190.0))
        tarifas = Support::Money.round2(desagio + advalorem + iof + outras)

        Records::Bordero.new(
          nro: format('%06d', sequence),
          client: client, company: control.company, carrier: control.carrier,
          control: control, month: month, date: date,
          wallet: control.modality == :auto_liquidavel ? 'Desconto' : 'Fomento',
          receivable_kind: stream.weighted('Duplicata' => 74, 'Cheque' => 14,
                                           'Cartão' => 7, 'ACC' => 3, 'PAC' => 2),
          resource_source: stream.weighted('Caixa' => 62, 'Fomento' => 22,
                                           'Garantia' => 8, 'Recompra' => 5, 'Comissaria' => 3),
          qtd_titulos: qtd_titulos, qtd_recusada: qtd_recusada, qtd_final: qtd_final,
          valor_bruto: valor_bruto, vlr_bruto_recusado: vlr_recusado,
          vlr_bruto_final: vlr_bruto_final,
          prz_med_pond_emp: prz_emp, prz_med_pond_bco: prz_bco,
          float_acordado: float_acordado, float_calculado: float_calculado,
          diferenca_float: float_calculado - float_acordado,
          # O **custo efetivo acordado** é o que a mesa negociou com a
          # contraparte, em % a.m., e é entrada de digitação — não derivado. Ele
          # nasce da mesma taxa nominal do borderô com o adicional de tarifa que
          # a negociação embute; sem ele o `Receivables::Calculator` não fecha
          # `calc_valor_liq_correto`, e o model recusa a gravação (presença).
          cst_efetivo_acordado: (nominal_tax + 0.21).round(4),
          nominal_tax: nominal_tax,
          tarifa_desagio: desagio, tarifa_advalorem: advalorem, tarifa_iof: iof,
          tarifa_outras: outras, valor_total_tarifas: tarifas,
          valor_liquido: Support::Money.round2(vlr_bruto_final - tarifas)
        )
      end

      # **A maioria dos borderôs não tem recusa.** Recusa em todos vira ruído; a
      # recusa parcial só é interessante quando é exceção — e o índice sobe na
      # retração sazonal, que é o que o gráfico de recusa mostra.
      def refusal(carrier, qtd_titulos, valor_bruto, stream)
        return [0, 0.0] unless stream.chance(carrier.refusal_rate * 4)

        ratio = stream.float(0.005, 0.12)
        qtd = [(qtd_titulos * ratio).round, 1].max
        qtd = [qtd, qtd_titulos - 1].min
        return [0, 0.0] if qtd <= 0

        [qtd, Support::Money.round2(valor_bruto * ratio)]
      end

      # Dia dentro do mês. No mês corrente a série para **na data-base** — borderô
      # com data futura é o tipo de detalhe que denuncia o seed.
      def day_in_month(month, base_date, stream)
        last = month.offset.zero? ? base_date.day : Date.new(month.year, month.month, -1).day
        Date.new(month.year, month.month, stream.int(1, [last, 1].max))
      end
    end
  end
end
