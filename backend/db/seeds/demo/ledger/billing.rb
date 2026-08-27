# frozen_string_literal: true

module Demo
  class Ledger
    # **Cobranças e recibos** (S6, dona por DEC-63) — o faturamento da gestora
    # sobre as operações que ela acompanhou.
    #
    # ## A cadeia é `charge → receipts → operation`, e nunca um atalho
    #
    # O comentário original da migration de 2022 é explícito: *"jamais
    # relacionar cobranças e ops diretamente, deve-se usar o receipt como
    # referência"*. Não há coluna de operação em `charges` e o razão respeita
    # isso: a cobrança **não conhece** operação nenhuma — ela conhece recibos, e
    # cada recibo conhece **uma** operação.
    #
    # ## Os sete totais de `charges` são DERIVADOS, e aqui eles fecham
    #
    # `value`, `risk_operations_value`, `structured_operations_value`,
    # `total_operations_value` e as três contagens são somas dos recibos —
    # `Charge#recalculate!` as reescreve a partir do banco. O razão as calcula
    # **da mesma lista** que produz os recibos, então o número que o escritor
    # grava é o número que o recálculo produziria. Há spec conferindo os dois.
    #
    # ## A remuneração é a tabela de preço, e ela vem antes do recibo
    #
    # `Remuneration` (S8) é a taxa que a gestora cobra por **tipo de operação**
    # em cada projeto, e é dela que `Receipt#fee` sai (`receipt.rb:61-63`). Este
    # módulo produz as duas coisas — a tabela de preço e os pacotes — pela
    # **mesma** função de taxa (`fee_for`), de forma que o número da tela de
    # Remunerações e o do recibo nunca divergem.
    #
    # ## `EST`: parte faturada, parte candidata — 27/08/2026
    #
    # As duas classes de remuneração eram semeadas (`LIQ` → `RiskOperationType`,
    # `EST` → `StructuredOperationType`), mas **todo recibo emitido era `LIQ`**:
    # os contadores de estruturada dos pacotes ficavam em zero e a classe `EST`
    # não era exercitada por dado nenhum. Toda linha da lista de Cobranças dizia
    # `0 est.`, e a coluna existia para não mostrar nada.
    #
    # O argumento antigo — *"não faturar deixa candidato para marcar ao vivo"* —
    # continua valendo, e é por isso que a divisão é por **estado do pacote**:
    #
    #  - os pacotes **já emitidos** (`done`) levam recibos `EST`, e é deles que
    #    saem os contadores e o valor de estruturada da lista;
    #  - os pacotes `editing` e `available` **não** levam — e as estruturadas
    #    que sobram continuam aparecendo em
    #    `Charges::ReceiptGenerator#candidates`, que é o que a apresentação
    #    marca ao vivo.
    #
    # `EST_BILLED_SHARE` é o teto do que se fatura por cliente, para que a lista
    # de candidatos nunca fique vazia.
    module Billing
      # **As lacunas escolhidas.** Nenhuma delas é sobra:
      #
      #  - `agroinsumos-cerrado` e `litoral-norte-servicos` são os dois menores
      #    da carteira e são faturados no contrato do grupo, não por pacote —
      #    a tela de Cobranças abre vazia neles de propósito, e é o que dá à
      #    apresentação um exemplo do estado vazio;
      #  - `tecnologia-ribeirao` entrou há dois meses e ainda não tem operação
      #    encerrada para faturar.
      WITHOUT_CHARGES = %w[agroinsumos-cerrado litoral-norte-servicos tecnologia-ribeirao].freeze

      # Quantos pacotes por cliente e quantos recibos em cada um. Faixa, não
      # número fixo: doze clientes com exatamente cinco cobranças é o tipo de
      # regularidade que denuncia dado gerado.
      CHARGES_PER_CLIENT = { grande: [6, 8], medio: [4, 6], pequeno: [3, 4],
                             recuperacao: [3, 5], entrante: [0, 0] }.freeze
      RECEIPTS_PER_CHARGE = [3, 9].freeze

      # Quantos recibos `EST` num pacote já emitido. Estruturada é operação
      # desenhada caso a caso, não esteira: um pacote com nove delas seria tão
      # implausível quanto nenhuma.
      RECEIPTS_EST_PER_CHARGE = [1, 3].freeze

      # No máximo esta fração das estruturadas encerradas de um cliente é
      # faturada. O resto é candidato — ver o cabeçalho.
      EST_BILLED_SHARE = 0.45

      # Abaixo deste índice o pacote é `editing`/`available` e **não** recebe
      # `EST`. Mesma fronteira de `state_for`.
      EST_FROM_CHARGE_INDEX = 2

      # A taxa de remuneração da gestora, em % sobre o valor da operação.
      # Faixa de mercado para consultoria de crédito estruturado — nunca
      # `rand(0..100)`, que é o defeito do seed do legado.
      FEE_RANGE = [0.28, 1.15].freeze

      # **A faixa acima é o envelope; a banda por porte é o que dá plausibilidade.**
      #
      # Sortear uniformemente dentro de `FEE_RANGE` produziria o grupo de R$ 180
      # mi pagando 1,09% e a distribuidora pequena pagando 0,31% — o inverso do
      # mercado. Desconto por volume é a primeira coisa que um diretor financeiro
      # confere numa tabela de preço, e é de graça acertar.
      #
      # Toda banda está **dentro** de `FEE_RANGE`, e as pontas do envelope são
      # usadas (0,28% no maior cliente, 1,15% no teto do entrante). O spec das
      # regras de coerência confere a contenção em vez de confiar nos números
      # escritos aqui.
      TIER_FEE_BAND = {
        grande: [0.28, 0.52],
        medio: [0.45, 0.78],
        pequeno: [0.62, 0.95],
        # Cliente em recuperação paga mais: risco maior e acompanhamento mais
        # intenso. É a mesma leitura que o razão já aplica ao limite e ao prazo.
        recuperacao: [0.70, 1.05],
        # Entrante ainda não tem volume para negociar desconto.
        entrante: [0.80, 1.15]
      }.freeze

      # A estruturada é desenhada caso a caso — não é esteira —, então custa mais
      # que a liquidável do mesmo cliente. O prêmio é multiplicativo e o
      # resultado continua preso a `FEE_RANGE`.
      STRUCTURED_FEE_PREMIUM = 1.18

      # As duas classes de remuneração e a classe de tipo que cada uma aponta.
      # São as mesmas duas de `Remuneration::OPERATION_TYPE_TYPES` e de
      # `Receipt::KINDS` — declaradas aqui como texto porque o razão é Ruby puro
      # e **não** carrega model (é o que o faz rodar antes de a tabela existir).
      OPERATION_TYPE_CLASSES = {
        'LIQ' => 'RiskOperationType',
        'EST' => 'StructuredOperationType'
      }.freeze

      module_function

      # **A tabela de preço**: uma remuneração por (cliente, classe, modalidade).
      #
      # A cobertura é DERIVADA do que o cliente opera — as modalidades dos
      # limites dele para `LIQ`, as das estruturadas dele para `EST` —, e não um
      # produto cartesiano de 12 × 4 × 2. Duas razões, nesta ordem:
      #
      # 1. **Toda linha da tela responde a "por que esta taxa existe?"** com uma
      #    operação no banco. Taxa cadastrada para modalidade que o cliente nunca
      #    operou é a linha que o cliente pergunta e ninguém sabe responder.
      # 2. **Toda remuneração tem candidato.** `Charges::ReceiptGenerator`
      #    procura operação sem recibo do tipo da remuneração; derivando das
      #    operações reais, nenhuma remuneração fica sem lista.
      def remunerations(clients, controls, structured_operations, rng)
        por_cliente_liq = controls.group_by { |c| c.client.slug }
        por_cliente_est = structured_operations.group_by { |o| o.client.slug }

        clients.flat_map do |client|
          modalidades = {
            'LIQ' => (por_cliente_liq[client.slug] || []).map(&:modality).uniq.sort,
            'EST' => (por_cliente_est[client.slug] || []).map(&:modality).uniq.sort
          }

          modalidades.flat_map do |kind, lista|
            lista.map { |modality| build_remuneration(client, kind, modality, rng) }
          end
        end
      end

      def build_remuneration(client, kind, modality, rng)
        Records::Remuneration.new(
          key: "#{client.slug}/#{kind.downcase}/#{modality}",
          client: client, kind: kind, modality: modality,
          operation_type_class: OPERATION_TYPE_CLASSES.fetch(kind),
          # O mesmo texto do título do tipo de operação — é o que o model copia
          # em todo save (`remuneration.rb:17-19`, decisão B-06). O razão o
          # carrega só para poder conferir a coerência sem tocar no banco; quem
          # grava a coluna é o callback do model.
          title: Cast::MODALITIES.fetch(modality),
          value: fee_for(client, kind, modality, rng)
        )
      end

      # **A ÚNICA fonte da taxa.** O recibo a copia daqui pela mesma chave — é o
      # que faz `receipts.fee` ser sempre igual a `remunerations.value`, como o
      # `Charges::ReceiptGenerator` produziria (contrato C2: um cálculo, um
      # dono). Antes, o recibo sorteava a própria taxa a cada linha, e o mesmo
      # cliente aparecia faturado a 0,42% num mês e a 0,91% no seguinte, na mesma
      # modalidade.
      #
      # O gerador é **derivado da chave de negócio** (`rng.keyed`), e não de um
      # fluxo posicional: acrescentar um cliente não muda a taxa de nenhum outro.
      # O prêmio da estruturada é aplicado à **banda**, e o sorteio vem depois.
      # Multiplicar o resultado e cortar no teto empilhava taxas: dois tipos do
      # mesmo cliente saíam com `1,1500%` cravado, que é exatamente o número
      # redondo que o §3 do desenho proíbe.
      def fee_for(client, kind, modality, rng)
        piso, teto = TIER_FEE_BAND.fetch(client.tier)
        if kind == 'EST'
          piso *= STRUCTURED_FEE_PREMIUM
          teto *= STRUCTURED_FEE_PREMIUM
        end
        piso = piso.clamp(FEE_RANGE.first, FEE_RANGE.last)
        teto = teto.clamp(FEE_RANGE.first, FEE_RANGE.last)

        rng.keyed(:remuneration, client.slug, kind, modality).float(piso, teto).round(4)
      end

      def build(clients, operations, base_date, rng, remunerations:, structured_operations: [])
        # A taxa vem da tabela de preço, nunca de um sorteio local.
        fees = remunerations.to_h { |r| [[r.client.slug, r.kind, r.modality], r] }
        by_client = operations.select { |o| o.state == :ended }.group_by { |o| o.client.slug }
        est_by_client = structured_operations.select(&:is_ended).group_by { |o| o.client.slug }
        charges = []

        clients.each do |client|
          next if WITHOUT_CHARGES.include?(client.slug)

          pool = (by_client[client.slug] || []).sort_by(&:contract_number)
          next if pool.empty?

          stream = rng.keyed(:billing, client.slug)
          min_count, max_count = CHARGES_PER_CLIENT.fetch(client.tier)
          count = min_count.zero? ? 0 : stream.int(min_count, max_count)
          cursor = 0

          # Só uma parte das estruturadas encerradas entra em pacote; o resto
          # fica como candidato para a demonstração ao vivo.
          pool_est = (est_by_client[client.slug] || []).sort_by(&:contract_number)
          faturaveis_est = pool_est.first((pool_est.length * EST_BILLED_SHARE).floor)
          cursor_est = 0

          count.times do |index|
            # O índice 0 é o pacote do mês corrente; os seguintes recuam um mês
            # cada. Datas relativas à data-base, nunca cravadas.
            months_back = index
            date = charge_date(base_date, months_back, stream)
            state = state_for(months_back)

            taken = pool[cursor, stream.int(*RECEIPTS_PER_CHARGE)] || []
            cursor += taken.length

            taken_est =
              if index >= EST_FROM_CHARGE_INDEX
                faturaveis_est[cursor_est, stream.int(*RECEIPTS_EST_PER_CHARGE)] || []
              else
                []
              end
            cursor_est += taken_est.length
            break if taken.empty? && taken_est.empty?

            charges << build_charge(client, date, state, taken, taken_est, index, fees)
          end
        end

        charges
      end

      def build_charge(client, date, state, operations, structured, index, fees)
        charge = Records::Charge.new(
          key: "#{client.slug}/cob-#{format('%02d', index + 1)}",
          client: client, date: date, state: state, receipts: []
        )

        charge.receipts =
          operations.map { |operation| build_receipt(charge, client, operation, fees, kind: 'LIQ') } +
          structured.map { |operation| build_receipt(charge, client, operation, fees, kind: 'EST') }

        est = charge.receipts.select { |r| r.kind == 'EST' }
        liq = charge.receipts - est

        charge.value = Support::Money.round2(charge.receipts.sum(&:value))
        charge.risk_operations_value = Support::Money.round2(liq.sum(&:operation_value))
        charge.structured_operations_value = Support::Money.round2(est.sum(&:operation_value))
        charge.total_operations_value =
          Support::Money.round2(charge.risk_operations_value + charge.structured_operations_value)
        charge.receipts_count = charge.receipts.length
        charge.risk_operations_count = liq.length
        charge.structured_operations_count = est.length
        charge
      end

      # **A taxa e o título saem da remuneração, não deste método.** É o que o
      # `Charges::ReceiptGenerator` faz (`fee = remuneration.value`,
      # `title = remuneration.title`), e reproduzi-lo aqui é o que garante que
      # um recibo semeado e um recibo gerado pela tela, para a mesma operação,
      # digam o mesmo número. `fetch` sem padrão de propósito: recibo cuja
      # modalidade não tem remuneração é defeito do razão, e tem de estourar no
      # spec, não virar `nil` no banco.
      def build_receipt(charge, client, operation, fees, kind: 'LIQ')
        remuneration = fees.fetch([client.slug, kind, modality_of(operation)])
        fee = remuneration.value
        operation_value = Support::Money.round2(operation.operation_value)

        Records::ChargeReceipt.new(
          charge: charge, client: client, operation: operation,
          kind: kind,
          remuneration: remuneration,
          title: remuneration.title,
          fee: fee,
          operation_value: operation_value,
          # `operation_value × (fee / 100)`, truncado em 2 casas — a fórmula do
          # `receipt.rb` de 2022, replicada (D-B14).
          value: Support::Money.round2(operation_value * (fee / 100.0)),
          date: operation.issue_date
        )
      end

      # A modalidade da operação de risco vem do LIMITE que a rege; a da
      # estruturada é atributo dela mesma (não há limite atrás de uma
      # estruturada). Uma linha, para o `build_receipt` não precisar saber qual
      # das duas está processando.
      def modality_of(operation)
        operation.respond_to?(:control) && operation.control ? operation.control.modality : operation.modality
      end

      # Dia útil plausível de fechamento: entre 3 e 12 do mês. O do mês corrente
      # nunca passa da data-base.
      def charge_date(base_date, months_back, stream)
        reference = base_date << months_back
        day = stream.int(3, 12)
        last = Date.new(reference.year, reference.month, -1).day
        candidate = Date.new(reference.year, reference.month, [day, last].min)
        candidate > base_date ? base_date : candidate
      end

      # A situação do pacote é função da **idade**: o que já foi emitido está
      # `done`, o do mês passado está `available` (fechado, aguardando emissão) e
      # o do mês corrente ainda está `editing`. É assim que a tela se comporta, e
      # é o que garante que as três pílulas de estado apareçam na lista.
      def state_for(months_back)
        case months_back
        when 0 then 'editing'
        when 1 then 'available'
        else 'done'
        end
      end
    end
  end
end
