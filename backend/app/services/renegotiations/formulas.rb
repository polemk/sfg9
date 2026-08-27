# frozen_string_literal: true

module Renegotiations
  # S9 / BE-204..BE-212, BE-219, BE-223 — **as fórmulas da renegociação, e nada
  # além delas**.
  #
  # Funções **puras** sobre números já carregados. Nenhuma consulta, nenhuma
  # gravação, nenhum `Date.today` implícito (a data entra por parâmetro). É isso
  # que permite a mesma linha de código atender a **pré-visualização** e a
  # **gravação** — o contrato **C2**, que numa tela de renegociação é o ponto mais
  # fácil de errar: se a simulação e o salvamento não produzirem exatamente os
  # mesmos números, o usuário digita um valor, vê um total e grava outro.
  #
  # ## DEC-30 / DEC-02: o que está aqui é REPLICADO, não corrigido
  #
  # O legado é sistema validado. Cada fórmula abaixo é a linha correspondente de
  # `../sfg/app/models/renegotiation.rb:89-183`,
  # `renegotiation_installment.rb:59-69` e `renegotiation_payment.rb:11-14`,
  # na **mesma ordem** e com os **mesmos pontos de arredondamento**. Três delas
  # parecem erro e **são replicadas de propósito** — se você veio consertar uma,
  # o golden test correspondente reprova, e é para isso que ele existe:
  #
  # 1. **A mora entra dos dois lados da conta da parcela.**
  #    `late_payment_value` soma ao DEVIDO (`installment_total_value`) **e** ao
  #    PAGO (`total_paid_value` de cada pagamento). No saldo da parcela os dois
  #    se cancelam — mas no agregado da renegociação **não**: `paid_value` conta
  #    a mora e `remaining_value` a ignora. "R$ Pago" e "R$ A Pagar" medem coisas
  #    diferentes (Q-B26).
  # 2. **A assimetria do "quanto falta".** `pending_main_value` pode ficar
  #    **negativo**; `remaining_value` é a soma de `pending_value` das parcelas,
  #    que tem **piso em zero**. Dois números para a mesma pergunta, com regras
  #    diferentes (Q-B22).
  # 3. **O VP sobrescreve "Valor Parcela".** `current_value` termina reatribuindo
  #    `current_installment_value`. Sempre que há juros > 0 e saldo em aberto, a
  #    coluna passa a mostrar outra coisa (D-46, Q-B25). **É um número que o
  #    cliente lê** — mudar exige reconciliação, não iniciativa.
  #
  # ## O que É corrigido, e por quê
  #
  # - **O estado "Inconsistente" volta a existir** (D-45). No legado
  #   `renegotiation.rb:118-123` escrevia o estado e a **linha seguinte o
  #   sobrescrevia**, então o filtro da tela nunca retornava nada. Aqui os quatro
  #   estados saem de UMA expressão. É a única mudança de VALOR desta unidade, e
  #   ela é deliberada: sem isso, dois dos quatro filtros da tela continuam
  #   inertes.
  # - **"Vencidas" deixa de ser fotografia de cron** (D-54 / OPS-190). A fórmula
  #   é a mesma; o que muda é **quando** ela roda.
  module Formulas
    module_function

    ZERO = BigDecimal(0)

    # ------------------------------------------------------------------
    # Parcela — `renegotiation_installment.rb:59-69`
    # ------------------------------------------------------------------
    # `late_payment_value` e `paid_value` vêm dos PAGAMENTOS (somados pelo
    # chamador); numa parcela recém-criada os dois são zero, que é exatamente o
    # que o `before_validation … on: [:create]` do legado fazia.
    #
    # Devolve o hash de derivados prontos para atribuição — o **mesmo** hash na
    # prévia e na gravação (C2).
    def installment(main_value:, interest_value:, monetary_correction_value:,
                    late_payment_value: ZERO, paid_value: ZERO)
      main = dec(main_value)
      juros = dec(interest_value)
      cm = dec(monetary_correction_value)
      mora = dec(late_payment_value)
      pago = dec(paid_value)

      main_with_interest = main + juros
      main_with_interest_cm = main_with_interest + cm
      # A mora entra no DEVIDO. Ver a nota 1 do cabeçalho.
      total = main_with_interest_cm + mora
      saldo = pago - total
      # **Piso em zero.** É daqui que nasce a assimetria com `pending_main_value`.
      pending = saldo.negative? ? total - pago : ZERO

      {
        main_value_with_interest: main_with_interest,
        main_value_with_interest_cm: main_with_interest_cm,
        late_payment_value: mora,
        installment_total_value: total,
        paid_value: pago,
        saldo: saldo,
        pending_value: pending,
        is_paid: pending <= ZERO
      }
    end

    # ------------------------------------------------------------------
    # Pagamento — `renegotiation_payment.rb:11-14`
    # ------------------------------------------------------------------
    # Piso em 0 para o atraso: pagamento adiantado não gera "dias negativos".
    def payment(date:, due_date:, installment_paid_value_with_interest_cm:, late_payment_value: ZERO)
      valor = dec(installment_paid_value_with_interest_cm)
      mora = dec(late_payment_value)
      atraso = date.present? && due_date.present? && date > due_date ? (date - due_date).to_i : 0

      { days_late: atraso, total_paid_value: valor + mora }
    end

    # ------------------------------------------------------------------
    # Renegociação — `renegotiation.rb:89-127`
    # ------------------------------------------------------------------
    # `installments` é uma lista de hashes com os derivados da parcela;
    # `payments` uma lista com `installment_paid_value_with_interest_cm`.
    # A ORDEM das atribuições abaixo é a do legado, linha a linha, porque em
    # aritmética de ponto flutuante a ordem é parte do resultado (DEC-02).
    #
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def aggregate(installments:, payments:, total_debt:, original_value:, desagio_value:,
                  operation_interest_rate:, today: Date.current)
      parcelas = installments.map { |i| i.transform_keys(&:to_sym) }
      pagamentos = payments.map { |p| p.transform_keys(&:to_sym) }

      out = {}
      out[:installments_count] = parcelas.size
      vencimentos = parcelas.filter_map { |i| i[:due_date] }.sort
      out[:first_due_date] = vencimentos.first
      out[:last_due_date] = vencimentos.last
      # `correct_value = total_debt` SEMPRE (D-47, Q-B24).
      out[:correct_value] = dec(total_debt)

      out[:installments_main_value] = soma(parcelas, :main_value)
      out[:installments_interest_value] = soma(parcelas, :interest_value)
      out[:installments_main_value_with_interest] =
        out[:installments_main_value] + out[:installments_interest_value]
      out[:installments_monetary_correction_value] = soma(parcelas, :monetary_correction_value)
      out[:installments_main_value_with_interest_cm] =
        out[:installments_main_value_with_interest] + out[:installments_monetary_correction_value]
      # `main_value` NÃO é `total_debt`: é o que as parcelas somam.
      out[:main_value] = out[:installments_main_value_with_interest_cm]

      out[:paid_value_with_interest_cm] = soma(pagamentos, :installment_paid_value_with_interest_cm)
      # **Pode ficar negativo** (Q-B22) — sem piso, ao contrário de `remaining_value`.
      out[:pending_main_value] = out[:main_value] - out[:paid_value_with_interest_cm]
      out[:paid_percent] =
        if out[:main_value].zero?
          # Guarda de divisão por zero. Acima de 100% é ACEITO.
          0
        else
          (100 * (out[:paid_value_with_interest_cm] / out[:main_value])).round(2)
        end
      out[:late_payment_value] = soma(parcelas, :late_payment_value)
      # "R$ Pago" CONTA a mora — e "R$ A Pagar", logo abaixo, a ignora.
      out[:paid_value] = out[:late_payment_value] + out[:paid_value_with_interest_cm]

      out[:remaining_value] = soma(parcelas, :pending_value)
      out[:paid_installments] = parcelas.count { |i| truthy?(i[:is_paid]) }
      # **Vencida = em aberto com vencimento anterior a hoje.** Mesma definição
      # do escopo `RenegotiationInstallment.overdue`, e é a única — o que mudou
      # foi deixar de depender do cron diário (D-54 / D-B6 / OPS-190).
      out[:overdue_installments] = parcelas.count do |i|
        !truthy?(i[:is_paid]) && i[:due_date].present? && i[:due_date] < today
      end
      # "A vencer" = total - pagas. **INCLUI as vencidas** (Q-B23). O nome mente;
      # a conta é essa, e é ela que entra no expoente do VP.
      out[:due_installments] = out[:installments_count] - out[:paid_installments]

      out[:total_value_with_desagio] = dec(original_value) - dec(desagio_value)

      out[:state] = state_for(installments_count: out[:installments_count],
                              installments_main_value: out[:installments_main_value],
                              correct_value: out[:correct_value],
                              remaining_value: out[:remaining_value])

      # A ordem importa: primeiro a soma do mês corrente…
      out[:current_installment_value] = current_installment_value(parcelas, today)
      # …e então o VP, que LÊ essa soma e **a sobrescreve** (D-46, Q-B25).
      vp = current_value(remaining_value: out[:remaining_value],
                         operation_interest_rate: operation_interest_rate,
                         current_installment_value: out[:current_installment_value],
                         due_installments: out[:due_installments])
      out[:current_value] = vp[:current_value]
      out[:current_installment_value] = vp[:current_installment_value]

      out
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # **A correção do D-45**, e a única mudança de valor desta unidade.
    #
    # No legado (`renegotiation.rb:118-123`):
    #
    #     state = installments_main_value < correct_value ? INCONSISTENT : OPEN
    #     state = remaining_value <= 0 ? CLOSED : OPEN     # ← apaga a linha acima
    #
    # A segunda linha reescreve o estado em **todos** os ramos, então
    # "Inconsistente" nunca chegava ao banco e o filtro da tela não retornava
    # nada. Aqui a sobrescrita só acontece no ramo que ela pretendia cobrir —
    # "liquidado". Consequência observável, declarada: uma renegociação em aberto
    # cujas parcelas **não cobrem** a dívida contratada passa a aparecer como
    # "Inconsistente" onde hoje aparece como "Pago". É o que os dois filtros
    # inertes existiam para mostrar.
    def state_for(installments_count:, installments_main_value:, correct_value:, remaining_value:)
      return Renegotiation::STATE_EMPTY if installments_count.zero?
      return Renegotiation::STATE_CLOSED if dec(remaining_value) <= ZERO
      return Renegotiation::STATE_INCONSISTENT if dec(installments_main_value) < dec(correct_value)

      Renegotiation::STATE_OPEN
    end

    # "Valor Parcela": soma das parcelas do MÊS CORRENTE. **Inclui a já paga** —
    # o legado filtra só por mês/ano (`renegotiation.rb:157-161`).
    def current_installment_value(parcelas, today = Date.current)
      parcelas
        .select { |i| i[:month].to_i == today.month && i[:year].to_i == today.year }
        .sum(ZERO) { |i| dec(i[:main_value_with_interest_cm]) }
    end

    # **VP — valor presente da dívida pela taxa acordada** (`:175-183`).
    #
    # Os dois `return` antecipados NÃO tocam em `current_installment_value`; só o
    # ramo final o sobrescreve. Replicado tal e qual.
    def current_value(remaining_value:, operation_interest_rate:, current_installment_value:, due_installments:)
      restante = dec(remaining_value)
      atual = dec(current_installment_value)

      return { current_value: ZERO, current_installment_value: atual } if restante <= ZERO
      if operation_interest_rate.to_f.zero?
        return { current_value: restante, current_installment_value: atual }
      end

      taxa = operation_interest_rate.to_f / 100.0
      n = due_installments.to_i
      vp = (atual * ((((1 + taxa)**n) - 1) / taxa)) / ((1.0 + taxa)**n)
      arredondado = dec(vp).round(2)

      # A reatribuição é o D-46. Os dois campos passam a mostrar o mesmo número.
      { current_value: arredondado, current_installment_value: arredondado }
    end

    # "Próxima parcela em aberto": vencimento **hoje ou no futuro**. Vencida
    # nunca é "próxima" — o legado usa `due_date >= hoje AND is_paid = 0`.
    def next_installment(parcelas, today = Date.current)
      parcelas
        .reject { |i| truthy?(i[:is_paid]) }
        .select { |i| i[:due_date].present? && i[:due_date] >= today }
        .min_by { |i| i[:due_date] }
    end

    # Consistência do LANÇAMENTO contra a dívida contratada (`:140-155`).
    # A referência é principal+juros, **sem** correção monetária — foi mudado a
    # pedido do cliente (`#7391 #7215`) e o comentário do legado registra isso.
    def unposted_value(total_debt:, installments_main_value_with_interest:)
      dec(total_debt) - dec(installments_main_value_with_interest)
    end

    def installment_status(total_debt:, installments_main_value_with_interest:)
      dec(installments_main_value_with_interest) == dec(total_debt) ? 'Consistente' : 'Inconsistente'
    end

    # ------------------------------------------------------------------
    def soma(colecao, campo)
      colecao.sum(ZERO) { |item| dec(item[campo]) }
    end

    def dec(valor)
      case valor
      when BigDecimal then valor
      when nil then ZERO
      when Integer then BigDecimal(valor)
      when Float then BigDecimal(valor, Float::DIG)
      when String then BigDecimal(valor)
      else BigDecimal(valor.to_s)
      end
    end

    def truthy?(valor)
      valor == true || valor == 1 || valor.to_s == '1' || valor.to_s == 'true'
    end
  end
end
