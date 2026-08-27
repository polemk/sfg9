# frozen_string_literal: true

module Demo
  class Ledger
    # Operações de risco, seus movimentos e o **saldo derivado deles**.
    #
    # Esta é a parte que a DEC-64 usou para justificar a fatia própria. O saldo
    # **não é um campo sorteado**: é o acumulado dos movimentos na ordem de
    # `sequence`. Se alguém sortear o saldo, o painel de exposição passa a mostrar
    # um número que a lista de movimentos não produz — e é isso que o cliente
    # confere.
    #
    # **Convenção de sinal (DEC-01):** o legado guarda a exposição **negativa** e
    # multiplica por −1 na tela (`limite_utilizado_on`). Replicamos: débito empurra
    # o saldo para baixo, crédito traz de volta a zero, e a exposição do painel é
    # `saldo × −1`. Inverter aqui daria números "mais bonitos" e diferentes dos do
    # legado, que é exatamente o que a DEC-01 proíbe.
    module Operations
      MOVEMENT_TYPES = {
        liberacao_do_recurso: { title: 'Liberação do Recurso', credit_type: 'D' },
        juros: { title: 'Juros', credit_type: 'D' },
        advalorem: { title: 'AdValorem', credit_type: 'D' },
        iof: { title: 'IOF', credit_type: 'D' },
        juros_de_mora: { title: 'Juros de Mora', credit_type: 'D' },
        transferencia_recebida: { title: 'Transferência Recebida', credit_type: 'D' },
        liquidacao: { title: 'Liquidação', credit_type: 'C' },
        valor_transferido: { title: 'Valor Transferido', credit_type: 'C' }
      }.freeze

      # Abaixo disto não vale abrir operação — e é a válvula que evita criar
      # operação de R$ 300 só porque sobrou essa folga no limite.
      MIN_TICKET = 25_000.0

      # Probabilidade de um controle abrir operação num mês. Calibrada para a
      # volumetria de §6 (~640 operações).
      MONTHLY_CHANCE = 0.40

      module_function

      def build(controls, months, base_date, rng)
        exposure = Hash.new(0.0)
        counters = Hash.new(0)
        operations = []

        controls.each do |control|
          months.each do |month|
            next unless month.offset >= control.carrier.available_from
            next unless Timeline.active?(control.client, month)

            stream = rng.keyed(:operations, control.key, month.offset)
            next unless stream.chance(MONTHLY_CHANCE)

            operation = build_operation(control, month, base_date, counters, exposure, stream)
            next if operation.nil?

            operations << operation
          end
        end

        operations.concat(utilization_top_ups(controls, operations, base_date, counters, rng))
        operations
      end

      # ------------------------------------------------------------------
      # Uma operação
      # ------------------------------------------------------------------
      def build_operation(control, month, base_date, counters, exposure, stream,
                          forced_value: nil, forced_state: nil)
        issue_date = Receivables.day_in_month(month, base_date, stream)
        term = stream.pick([30, 45, 60, 75, 90, 120])
        due_date = issue_date + term
        agreed_rate = negotiated_rate(control, stream)

        state = forced_state || decide_state(month, due_date, base_date, stream)
        headroom = (control.limite * control.target_utilization) - exposure[control.key]
        factor = charge_factor(agreed_rate, term)

        value =
          if forced_value
            forced_value
          elsif state == :ended
            Support::Money.natural(control.limite * stream.tailed(0.06, 0.55), stream)
          else
            cap = headroom / factor
            return nil if cap < MIN_TICKET

            Support::Money.natural([cap * stream.tailed(0.25, 0.98), MIN_TICKET].max, stream)
          end

        counters[control.client.slug] += 1
        operation = Records::Operation.new(
          contract_number: format('CT-%<year>d-%<seq>05d',
                                  year: issue_date.year, seq: counters[control.client.slug]),
          client: control.client, company: control.company, carrier: control.carrier,
          control: control, month: month,
          issue_date: issue_date, due_date: due_date,
          operation_value: value, agreed_rate: agreed_rate, state: state,
          movements: [], balance: 0.0
        )

        build_movements(operation, term, base_date, stream)
        exposure[control.key] += -operation.balance if state != :ended
        operation
      end

      # A taxa da operação **é a do controle**, com até 0,15 p.p. de negociação
      # pontual (§7, regra 2). Operação a 2,1% num controle de 3,0% é incoerência
      # que quem é do mercado vê na primeira linha.
      def negotiated_rate(control, stream)
        (control.taxa + stream.float(-0.15, 0.15)).round(4)
      end

      # Quanto os encargos inflam o saldo em relação ao principal. Serve para
      # dimensionar a operação **antes** de gerar os movimentos, e é o que garante
      # que a soma das vivas caiba no limite.
      def charge_factor(agreed_rate, term)
        1.0 + ((agreed_rate / 100.0) * (term / 30.0)) + 0.005 +
          (Support::Money::IOF_DAILY_RATE * term) + Support::Money::IOF_ADDITIONAL_RATE
      end

      # Operação antiga viva é implausível: o giro do desconto é de 30 a 120 dias.
      # Por isso o estado depende da **idade**, e não de um sorteio uniforme — e é
      # o que produz naturalmente os ~70% encerradas de §6.
      def decide_state(month, due_date, base_date, stream)
        return :ended if month.offset < -7

        overdue_possible = due_date < base_date
        if overdue_possible
          stream.weighted(ended: 74, live: 16, overdue: 10)
        else
          stream.weighted(ended: 22, live: 78)
        end
      end

      # ------------------------------------------------------------------
      # Movimentos — o saldo sai daqui, e só daqui
      # ------------------------------------------------------------------
      # **O movimento vive DENTRO da janela da operação.** `RiskMovement` reprova
      # data fora de `[issue_date, due_date]` (`date_inside_operation_window`), e
      # a regra é do domínio, não do escritor: a mora de uma operação vencida é
      # lançada NO vencimento, não no dia em que alguém a percebeu.
      #
      # O grampo mora aqui, e não no escritor, porque o saldo do razão tem de ser
      # o mesmo que o banco vai ter — razão que produz data que o banco recusa é
      # razão que descreve um sistema que não existe.
      def inside_window(operation, date)
        return date if operation.issue_date.nil? || operation.due_date.nil?

        date.clamp(operation.issue_date, operation.due_date)
      end

      # **A cadeia é ordenada por DATA, e o saldo é recalculado nessa ordem.**
      #
      # O sistema lê o saldo pelo último movimento em `(date, created_at)`
      # (`RiskOperation#balance_on`, BE-266) — nunca pela ordem em que os
      # lançamentos foram criados. Os movimentos nascem aqui numa ordem lógica
      # (liberação, IOF, ad valorem, juros, liquidação) que **não** é a ordem
      # cronológica: os juros vencem perto do vencimento e uma liquidação parcial
      # costuma acontecer antes.
      #
      # Sem esta normalização o `balance` gravado na operação era o da ordem
      # lógica e o `balance_on` devolvia o da ordem cronológica: dois números
      # diferentes para a mesma operação, um na lista e outro no painel de risco.
      # A soma não muda — a ordem, sim, e neste domínio a ordem é o resultado
      # (DEC-02).
      #
      # `sort_by.with_index` mantém a ordem de inserção no empate de data, que é
      # o que `created_at` faz no banco: o escritor grava na ordem de `sequence`.
      def normalize_chain!(operation)
        ordered = operation.movements.each_with_index.sort_by { |m, i| [m.date, i] }.map(&:first)
        balance = 0.0

        ordered.each_with_index do |movement, index|
          signed = movement.credit_type == 'D' ? -movement.value.abs : movement.value.abs
          balance = Support::Money.round2(balance + signed)
          movement.sequence = index + 1
          movement.balance = balance
        end

        operation.movements = ordered
        operation.balance = balance
      end

      def build_movements(operation, term, base_date, stream, plain: false)
        balance = 0.0
        sequence = 0
        value = operation.operation_value

        push = lambda do |type_key, amount, date|
          sequence += 1
          signed = MOVEMENT_TYPES.fetch(type_key)[:credit_type] == 'D' ? -amount.abs : amount.abs
          balance = Support::Money.round2(balance + signed)
          operation.movements << Records::Movement.new(
            operation: operation, sequence: sequence, type_key: type_key,
            credit_type: MOVEMENT_TYPES.fetch(type_key)[:credit_type],
            date: inside_window(operation, date), value: Support::Money.round2(amount.abs),
            balance: balance
          )
        end

        push.call(:liberacao_do_recurso, value, operation.issue_date)
        push.call(:iof, Support::Money.iof(value, term), operation.issue_date)
        push.call(:advalorem, Support::Money.round2(value * stream.float(0.003, 0.005)),
                  operation.issue_date)
        push.call(:juros, Support::Money.monthly_interest(value, operation.agreed_rate, term),
                  operation.issue_date + [term - 1, 1].max)

        # **A "Transferência Recebida" SAIU daqui, e não é perda de cobertura.**
        #
        # Ela era lançada solta em 12% das operações comuns: 105 movimentos de
        # transferência **sem contrapartida** e sem `pair_id`. O sistema não
        # consegue produzir isso — `is_transfer` está fora de
        # `RiskMovementType.manual` (o usuário não pode lançar) e o único
        # caminho é `Risk::TransferService`, que **sempre** cria as duas pontas
        # e cruza o `pair_id`. Era dado que a tela mostrava e que nenhum
        # caminho do produto criaria.
        #
        # O par de verdade agora vive onde ele existe: nas operações estáticas
        # pré ↔ antecipação (`Ledger#static_transfers`, `Writers::StaticTransfers`).

        if operation.state == :overdue
          late_days = (base_date - operation.due_date).to_i
          push.call(:juros_de_mora,
                    Support::Money.round2(-balance * 0.0333 * (late_days / 30.0)),
                    operation.due_date + [late_days, 1].max)
        end

        case plain ? :plain : operation.state
        when :ended
          settle!(operation, push, balance, base_date, stream)
        when :live
          if stream.chance(0.38)
            partial = Support::Money.round2(-balance * stream.float(0.18, 0.55))
            push.call(:liquidacao, partial,
                      [operation.issue_date + stream.int(10, term), base_date].min)
          end
        end

        normalize_chain!(operation)
      end

      # Encerrar é **zerar**: a última liquidação vale exatamente o que restava.
      # É o que faz `saldo = 0` ser um fato do razão, não um arredondamento.
      # **A liquidação é o ÚLTIMO lançamento da cadeia, sempre.**
      #
      # O valor que ela quita é o saldo final, juros incluídos. Datá-la antes do
      # lançamento de juros deixava o saldo **positivo** entre as duas datas — e
      # como `balance_on` lê o último movimento ATÉ a data, o painel de risco
      # mostrava exposição **negativa** (`-6.322,61`, `-1,41%` do limite) para
      # uma operação encerrada cujos juros só entram no mês que vem. Achado
      # abrindo a tela; a soma final estava certa, o meio do caminho não.
      def settle!(operation, push, balance, base_date, stream)
        outstanding = -balance
        settle_date = [operation.due_date + stream.int(-3, 6), base_date].min
        settle_date = [settle_date, operation.issue_date + 1].max
        piso = operation.movements.map(&:date).max
        settle_date = [[settle_date, piso].max, operation.due_date].min

        if stream.chance(0.30)
          partial = Support::Money.round2(outstanding * stream.float(0.25, 0.6))
          push.call(:liquidacao, partial, [settle_date - stream.int(5, 25), operation.issue_date + 1].max)
          outstanding = Support::Money.round2(outstanding - partial)
        end

        push.call(:liquidacao, outstanding, settle_date)
      end

      # ------------------------------------------------------------------
      # Consumo de limite — a faixa que a tela de risco precisa mostrar
      # ------------------------------------------------------------------
      # **O "limite utilizado" do legado NÃO é o principal em aberto**, e foi
      # medindo o banco que isto ficou escrito.
      #
      # `RiskOperation` nasce com `original_balance = −|valor|` e o
      # `after_create` lança um movimento de **Liberação do Recurso** de valor
      # igual ao principal (`../sfg/app/models/risk_operation.rb:34,39-52`,
      # replicado em BE-264). Na cadeia do sistema — `balance = anterior +
      # (credit_type_value × valor)`, com **D = +1 e C = −1**
      # (`risk_movement_type.rb:53-61`) — a liberação **cancela** o principal:
      # o saldo de uma operação recém-aberta é **zero**. Daí
      # `limite_utilizado_on = saldo × −1` (DEC-01) sair como
      #
      #     utilizado = Σ liquidações − Σ encargos
      #
      # das operações **vigentes na data**. Não é o que a intuição financeira
      # diz, e não é nosso para consertar: DEC-01 e DEC-30 mandam replicar a
      # convenção do legado, e o `parity-ledger` trava os números. Registrado em
      # `upstream-flags.md`.
      #
      # A consequência prática para o seed é toda: **o alvo de utilização só se
      # realiza por LIQUIDAÇÃO dentro da janela**. O mecanismo anterior
      # dimensionava a operação de reforço pelo saldo do razão — que usa a
      # convenção oposta (débito empurra para baixo, a partir de zero) — e por
      # isso ele "acertava" 92% no razão enquanto o banco mostrava 14%. Os dois
      # estavam certos, medindo coisas diferentes; este é o mesmo modo de falha
      # da tarefa 8.14, uma camada mais fundo.
      #
      # O prazo é longo de propósito: a operação de amortização precisa estar
      # **viva hoje** (`issue_date ≤ hoje ≤ due_date`), senão ela sai da janela
      # de `operations_on` e não conta para limite nenhum.
      AMORTIZATION_TERM = 150

      # A exposição de uma operação **como o sistema a calcula** — a fórmula
      # acima, replicada em Ruby puro para que o razão possa mirar o número que
      # a tela vai mostrar sem depender de nenhum model.
      #
      # Ela convive com `operation.balance` (a convenção própria do razão, que
      # parte de zero) e **não** a substitui: o `balance` é o saldo devedor
      # econômico, usado para dimensionar operação contra limite; este é o que a
      # coluna "Lim. util" exibe.
      def legacy_exposure(operation, base_date)
        return 0.0 if operation.issue_date.nil? || operation.due_date.nil?
        return 0.0 unless operation.issue_date <= base_date && base_date <= operation.due_date

        saldo = -operation.operation_value
        operation.movements.each do |movement|
          next if movement.date > base_date

          saldo += (movement.credit_type == 'D' ? 1 : -1) * movement.value
        end
        Support::Money.round2(-saldo)
      end

      # Fecha a distância entre o consumo que a geração comum produziu e o alvo
      # do plano, com **uma** operação parcialmente amortizada por limite.
      def utilization_top_ups(controls, operations, base_date, counters, rng)
        atual = Hash.new(0.0)
        operations.each { |o| atual[o.control.key] += legacy_exposure(o, base_date) }

        controls.select { |c| (c.target_utilization || 0) >= Controls::FORCED_UTILIZATION_FLOOR }
                .sort_by(&:key)
                .filter_map do |control|
          alvo = control.limite * control.target_utilization
          faltando = alvo - atual[control.key]
          next if faltando < MIN_TICKET

          amortized_operation(control, faltando, base_date, counters, rng.keyed(:utilization, control.key))
        end
      end

      # A operação que carrega o consumo: aberta há dois a três meses, **viva**,
      # com uma amortização parcial grande — o caso mais comum de limite
      # apertado na vida real, e o único que a fórmula do legado enxerga.
      def amortized_operation(control, exposure, base_date, counters, stream)
        agreed_rate = negotiated_rate(control, stream)
        issue_date = base_date - stream.int(45, 100)
        # O principal é MAIOR que a amortização: quitar tudo encerraria a
        # operação e zeraria o consumo no dia seguinte.
        value = Support::Money.natural(exposure * stream.float(1.14, 1.42), stream)
        counters[control.client.slug] += 1

        operation = Records::Operation.new(
          contract_number: format('CT-%<year>d-%<seq>05d',
                                  year: issue_date.year, seq: counters[control.client.slug]),
          client: control.client, company: control.company, carrier: control.carrier,
          control: control, month: nil,
          issue_date: issue_date, due_date: issue_date + AMORTIZATION_TERM,
          operation_value: value, agreed_rate: agreed_rate, state: :live,
          movements: [], balance: 0.0
        )
        build_amortization_movements(operation, exposure, base_date, stream)
        operation
      end

      # Os encargos entram **antes** da data-base — inclusive os juros, que no
      # caminho comum vencem junto com a operação. É o que faz a amortização ser
      # dimensionável: `utilizado = liquidação − encargos`, e encargo lançado
      # para o mês que vem não está na conta de hoje.
      def build_amortization_movements(operation, exposure, base_date, stream)
        value = operation.operation_value
        iof = Support::Money.iof(value, AMORTIZATION_TERM)
        advalorem = Support::Money.round2(value * stream.float(0.003, 0.005))
        corridos = (base_date - operation.issue_date).to_i
        juros = Support::Money.monthly_interest(value, operation.agreed_rate, corridos)
        encargos = Support::Money.round2(iof + advalorem + juros)

        push = movement_pusher(operation)
        push.call(:liberacao_do_recurso, value, operation.issue_date)
        push.call(:iof, iof, operation.issue_date)
        push.call(:advalorem, advalorem, operation.issue_date)
        push.call(:juros, juros, base_date - 3)
        push.call(:liquidacao, Support::Money.round2(exposure + encargos), base_date - 1)

        normalize_chain!(operation)
      end

      # O mesmo empilhador de `build_movements`, extraído para que a operação de
      # amortização não precise duplicar a convenção de sinal do razão.
      def movement_pusher(operation)
        lambda do |type_key, amount, date|
          operation.movements << Records::Movement.new(
            operation: operation, sequence: operation.movements.length + 1, type_key: type_key,
            credit_type: MOVEMENT_TYPES.fetch(type_key)[:credit_type],
            date: inside_window(operation, date), value: Support::Money.round2(amount.abs),
            balance: 0.0
          )
        end
      end

      # ------------------------------------------------------------------
      # Operações estruturadas — mesmas 4 modalidades, muito menos frequentes
      # ------------------------------------------------------------------
      # ------------------------------------------------------------------
      # A TRANSFERÊNCIA pré → antecipação (BE-275)
      # ------------------------------------------------------------------
      # **O par estático não tinha nada para mostrar.** Medido: as 78 operações
      # estáticas do seed (39 pares) estavam com saldo zero e **zero
      # movimentos** — abrir uma delas na apresentação mostrava uma operação
      # morta, e o botão "Transferir" não tinha o que demonstrar.
      #
      # Quem grava o par é o **serviço do sistema** (`Risk::TransferService`),
      # não o razão: é ele que decide o sinal de cada ponta, cruza o `pair_id` e
      # refaz as duas cadeias de saldo. O razão só diz **onde** e **quanto** —
      # que é a mesma divisão de trabalho do agregado da renegociação.
      #
      # O valor sai do LIMITE do controle, não de um número solto: transferir
      # 18% de um teto de R$ 800 mil é plausível; R$ 12 mil num teto de R$ 900
      # mil não conta história nenhuma.
      STATIC_TRANSFER_CLIENTS = %w[alianca-metalurgica serra-azul-textil].freeze

      # As duas modalidades com `has_pre_faturamento` — são elas que abrem par
      # estático (`Risk::StaticPairService`).
      PRE_MODALITIES = %i[auto_liquidavel comissaria].freeze

      def static_transfers(controls, base_date, rng)
        STATIC_TRANSFER_CLIENTS.filter_map do |slug|
          control = candidate_control(controls, slug)
          next if control.nil?

          stream = rng.keyed(:static_transfer, control.key)
          Records::StaticTransfer.new(
            control: control,
            value: Support::Money.natural(control.limite * stream.float(0.12, 0.22), stream),
            date: base_date - stream.int(6, 28)
          )
        end
      end

      # O controle escolhido é o **de menor chave** entre os que abrem par e que
      # o plano de utilização NÃO usa. Determinístico (o roteiro precisa saber
      # onde clicar) e fora do plano, para que a exposição da transferência não
      # empurre um limite planejado para outra faixa da DEC-116.
      def candidate_control(controls, slug)
        controls.select { |c| c.client.slug == slug && PRE_MODALITIES.include?(c.modality) }
                .reject { |c| (c.target_utilization || 0) >= Controls::FORCED_UTILIZATION_FLOOR }
                .min_by(&:key)
      end

      def build_structured(controls, months, base_date, rng)
        counters = Hash.new(0)
        controls.each_with_object([]) do |control, acc|
          months.each do |month|
            next unless month.offset >= control.carrier.available_from
            next unless Timeline.active?(control.client, month)

            stream = rng.keyed(:structured, control.key, month.offset)
            next unless stream.chance(0.068)

            issue_date = Receivables.day_in_month(month, base_date, stream)
            term = stream.pick([60, 90, 120, 180])
            value = Support::Money.natural(control.limite * stream.tailed(0.08, 0.42), stream)
            ended = (issue_date + term) < base_date
            counters[control.client.slug] += 1

            acc << Records::StructuredOperation.new(
              contract_number: format('EST-%<year>d-%<seq>04d',
                                      year: issue_date.year, seq: counters[control.client.slug]),
              client: control.client, company: control.company, carrier: control.carrier,
              modality: control.modality, issue_date: issue_date,
              due_date: issue_date + term, operation_value: value,
              agreed_rate: negotiated_rate(control, stream),
              is_ended: ended,
              # Mesma convenção de sinal do risco (DEC-01): saldo negativo.
              balance: ended ? 0.0 : -value
            )
          end
        end
      end
    end
  end
end
