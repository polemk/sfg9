# frozen_string_literal: true

require 'rails_helper'

# S9 / tarefas 4.1–4.11 — **os golden tests da renegociação** (D-B3 / D-114).
#
# ## De onde vêm estes números
#
# O legado **não tem um único teste** (D-114). Os valores abaixo não foram
# escritos à mão nem conferidos "de cabeça": foram **produzidos executando as
# expressões do legado**, copiadas verbatim de
# `../sfg/app/models/renegotiation.rb:89-183`,
# `renegotiation_installment.rb:59-69` e `renegotiation_payment.rb:11-14` num
# script Ruby puro, sem Rails e sem banco. O que está aqui como literal é a saída
# daquele script.
#
# ## Para que servem
#
# **Para reprovar quem "consertar" a conta.** O DEC-30 é o princípio governante
# desta migração: o legado é sistema validado, e regra, cálculo e dado são
# replicados **mesmo quando a fórmula parece errada**. Três destas fórmulas
# parecem erro e são replicadas de propósito — se você chegou aqui porque um
# exemplo reprovou depois de você "melhorar" alguma coisa, **é este arquivo
# dizendo que a melhoria muda um número que o cliente lê**.
#
# ## A ÚNICA divergência deliberada, e ela está no cenário C
#
# `state`. No legado (`renegotiation.rb:118-123`) a linha que escreve
# "Inconsistente" é **sobrescrita pela seguinte**, então o estado nunca chegava ao
# banco e dois dos quatro filtros da tela não retornavam nada (**D-45**, **D-49**).
# O cenário C documenta os dois valores lado a lado: o que o legado grava hoje
# ("Pago") e o que o ai9 grava ("Inconsistente"). É mudança de valor, é
# deliberada, e está escrita.
#
# ## Uma afirmação do material da fatia que a extração REPROVOU
#
# O `tasks.md` (4.10) e o `design.md` (§1) dizem que, por a mora entrar dos dois
# lados da conta, **"pagar só a mora pode quitar a parcela"**. **Não pode.** A
# extração (cenário E) mostra que a mora entra no devido E no pago pelo mesmo
# valor e **se cancela exatamente**: `pending_value` de uma parcela de R$ 1.000,00
# que recebeu R$ 0,01 de principal e R$ 500,00 de mora é **999,99**, não zero.
# O que a mora realmente distorce está um nível acima, no agregado: `paid_value`
# CONTA a mora (500,01) e `remaining_value` a IGNORA (999,99) — dois números que
# o cliente lê lado a lado e que não fecham entre si. É esse o efeito, e é ele que
# o cenário E trava.
RSpec.describe Renegotiations::Formulas do
  # Constrói parcelas derivadas do mesmo jeito que a gravação faz.
  def parcela(due_date:, main:, interest: '0.00', cm: '0.00', pagamentos: [])
    derivados_pag = pagamentos.map do |p|
      described_class.payment(date: p[:date], due_date: due_date,
                              installment_paid_value_with_interest_cm: p[:cm],
                              late_payment_value: p[:late])
    end
    mora = pagamentos.sum(BigDecimal(0)) { |p| BigDecimal(p[:late]) }
    pago = derivados_pag.sum(BigDecimal(0)) { |d| d[:total_paid_value] }

    base = { due_date: due_date, month: due_date.month, year: due_date.year,
             main_value: BigDecimal(main), interest_value: BigDecimal(interest),
             monetary_correction_value: BigDecimal(cm) }

    base.merge(
      described_class.installment(main_value: base[:main_value],
                                  interest_value: base[:interest_value],
                                  monetary_correction_value: base[:monetary_correction_value],
                                  late_payment_value: mora, paid_value: pago)
    )
  end

  def pagamentos_de(*parcelas_com_pagamento)
    parcelas_com_pagamento.flatten.map { |p| { installment_paid_value_with_interest_cm: BigDecimal(p[:cm]) } }
  end

  # ------------------------------------------------------------------
  # Cenário A — nominal (tarefas 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 4.8)
  # ------------------------------------------------------------------
  describe 'cenário A — 3 parcelas, 1 quitada por pagamento com mora' do
    let(:hoje) { Date.new(2025, 2, 15) }
    let(:parcelas) do
      [
        parcela(due_date: Date.new(2025, 1, 10), main: '1000.00', interest: '50.00', cm: '10.00',
                pagamentos: [{ date: Date.new(2025, 1, 20), cm: '1060.00', late: '25.00' }]),
        parcela(due_date: Date.new(2025, 2, 10), main: '1000.00', interest: '50.00', cm: '10.00'),
        parcela(due_date: Date.new(2025, 3, 10), main: '1000.00', interest: '50.00', cm: '10.00')
      ]
    end
    let(:agregado) do
      described_class.aggregate(installments: parcelas,
                                payments: pagamentos_de({ cm: '1060.00' }),
                                total_debt: BigDecimal('3000.00'),
                                original_value: BigDecimal('3500.00'),
                                desagio_value: BigDecimal('500.00'),
                                operation_interest_rate: 0.0, today: hoje)
    end

    # 4.10 — recálculo da parcela: mora, total, pago, saldo, is_paid
    it 'deriva a parcela quitada exatamente como o legado' do
      p1 = parcelas.first
      expect(p1[:main_value_with_interest]).to eq(BigDecimal('1050.00'))
      expect(p1[:main_value_with_interest_cm]).to eq(BigDecimal('1060.00'))
      expect(p1[:late_payment_value]).to eq(BigDecimal('25.00'))
      # A mora entra no DEVIDO…
      expect(p1[:installment_total_value]).to eq(BigDecimal('1085.00'))
      # …e no PAGO, pelo mesmo valor.
      expect(p1[:paid_value]).to eq(BigDecimal('1085.00'))
      expect(p1[:saldo]).to eq(BigDecimal('0.00'))
      expect(p1[:pending_value]).to eq(0)
      expect(p1[:is_paid]).to be(true)
    end

    it 'deriva a parcela em aberto com saldo NEGATIVO e pendente POSITIVO' do
      p2 = parcelas[1]
      expect(p2[:saldo]).to eq(BigDecimal('-1060.00'))
      expect(p2[:pending_value]).to eq(BigDecimal('1060.00'))
      expect(p2[:is_paid]).to be(false)
    end

    # 4.11 — days_late e total_paid_value
    it 'calcula days_late e total_paid_value do pagamento' do
      atrasado = described_class.payment(date: Date.new(2025, 1, 20), due_date: Date.new(2025, 1, 10),
                                         installment_paid_value_with_interest_cm: BigDecimal('1060.00'),
                                         late_payment_value: BigDecimal('25.00'))
      expect(atrasado[:days_late]).to eq(10)
      expect(atrasado[:total_paid_value]).to eq(BigDecimal('1085.00'))

      # Pagamento ADIANTADO não gera dias negativos — piso em 0.
      adiantado = described_class.payment(date: Date.new(2025, 1, 5), due_date: Date.new(2025, 1, 10),
                                          installment_paid_value_with_interest_cm: BigDecimal('100.00'),
                                          late_payment_value: BigDecimal(0))
      expect(adiantado[:days_late]).to eq(0)
    end

    # 4.1 — somas de principal, juros e CM; main_value
    it 'soma principal, juros e correção monetária' do
      expect(agregado[:installments_main_value]).to eq(BigDecimal('3000.00'))
      expect(agregado[:installments_interest_value]).to eq(BigDecimal('150.00'))
      expect(agregado[:installments_main_value_with_interest]).to eq(BigDecimal('3150.00'))
      expect(agregado[:installments_monetary_correction_value]).to eq(BigDecimal('30.00'))
      expect(agregado[:installments_main_value_with_interest_cm]).to eq(BigDecimal('3180.00'))
      # `main_value` NÃO é `total_debt` (3000): é o que as parcelas somam.
      expect(agregado[:main_value]).to eq(BigDecimal('3180.00'))
    end

    # 4.2 — pago, mora, pendente
    it 'calcula pago, mora e pendente — e a MORA conta num, não no outro' do
      expect(agregado[:paid_value_with_interest_cm]).to eq(BigDecimal('1060.00'))
      expect(agregado[:late_payment_value]).to eq(BigDecimal('25.00'))
      # "R$ Pago" CONTA a mora…
      expect(agregado[:paid_value]).to eq(BigDecimal('1085.00'))
      # …e "R$ A Pagar" a ignora.
      expect(agregado[:remaining_value]).to eq(BigDecimal('2120.00'))
      expect(agregado[:pending_main_value]).to eq(BigDecimal('2120.00'))
    end

    # 4.3 — paid_percent
    it 'calcula o percentual pago com 2 casas' do
      expect(agregado[:paid_percent]).to eq(BigDecimal('33.33'))
    end

    # 4.4 — contagens
    it 'conta pagas, vencidas e "a vencer" — e "a vencer" INCLUI as vencidas' do
      expect(agregado[:paid_installments]).to eq(1)
      # Parcela 2 venceu em 10/02 e hoje é 15/02.
      expect(agregado[:overdue_installments]).to eq(1)
      # 3 - 1 = 2, e as 2 incluem a vencida (Q-B23). O nome mente; a conta é essa.
      expect(agregado[:due_installments]).to eq(2)
    end

    # 4.5 — contagem, datas, deságio, correct_value
    it 'deriva contagem, datas, deságio e correct_value' do
      expect(agregado[:installments_count]).to eq(3)
      expect(agregado[:first_due_date]).to eq(Date.new(2025, 1, 10))
      expect(agregado[:last_due_date]).to eq(Date.new(2025, 3, 10))
      expect(agregado[:total_value_with_desagio]).to eq(BigDecimal('3000.00'))
      # SEMPRE igual a total_debt (D-47, Q-B24).
      expect(agregado[:correct_value]).to eq(BigDecimal('3000.00'))
    end

    # 4.7 — unposted_value e installment_status
    it 'apura a consistência do lançamento contra a dívida contratada' do
      # A referência é principal+juros (3150), SEM correção monetária — mudado a
      # pedido do cliente no legado (`#7391 #7215`).
      expect(described_class.unposted_value(
               total_debt: BigDecimal('3000.00'),
               installments_main_value_with_interest: agregado[:installments_main_value_with_interest]
             )).to eq(BigDecimal('-150.00'))
      expect(described_class.installment_status(
               total_debt: BigDecimal('3000.00'),
               installments_main_value_with_interest: agregado[:installments_main_value_with_interest]
             )).to eq('Inconsistente')
    end

    # 4.8 — parcela do mês e próxima em aberto
    it 'soma a parcela do MÊS corrente e acha a próxima em aberto' do
      # Fevereiro: só a parcela 2. **Inclui a já paga** se houver — o legado
      # filtra só por mês/ano.
      expect(agregado[:current_installment_value]).to eq(BigDecimal('1060.00'))
      # A próxima em aberto é 10/03: a de 10/02 já VENCEU, e vencida nunca é
      # "próxima".
      proxima = described_class.next_installment(parcelas, hoje)
      expect(proxima[:due_date]).to eq(Date.new(2025, 3, 10))
      expect(proxima[:main_value_with_interest_cm]).to eq(BigDecimal('1060.00'))
    end

    it 'a taxa zero faz o VP devolver o próprio saldo, sem sobrescrever nada' do
      expect(agregado[:current_value]).to eq(BigDecimal('2120.00'))
      # `current_installment_value` NÃO foi tocado: os dois `return` antecipados
      # do legado não passam pela reatribuição.
      expect(agregado[:current_installment_value]).to eq(BigDecimal('1060.00'))
    end

    it 'o estado é "Pago" — as parcelas cobrem a dívida e ainda falta pagar' do
      expect(agregado[:state]).to eq('Pago')
    end
  end

  # ------------------------------------------------------------------
  # Cenário B — a assimetria (tarefa 4.2 / Q-B22) e o >100% (4.3)
  # ------------------------------------------------------------------
  describe 'cenário B — pagamento MAIOR que a parcela' do
    let(:parcelas) do
      [parcela(due_date: Date.new(2025, 1, 10), main: '1000.00',
               pagamentos: [{ date: Date.new(2025, 1, 5), cm: '1200.00', late: '0.00' }])]
    end
    let(:agregado) do
      described_class.aggregate(installments: parcelas, payments: pagamentos_de({ cm: '1200.00' }),
                                total_debt: BigDecimal('1000.00'), original_value: BigDecimal('1000.00'),
                                desagio_value: BigDecimal(0), operation_interest_rate: 0.0,
                                today: Date.new(2025, 2, 15))
    end

    it 'deixa pending_main_value NEGATIVO e remaining_value em ZERO' do
      # **É o mesmo "quanto falta", medido com duas regras.** Um sem piso, outro
      # com piso em zero. Replicado (Q-B22).
      expect(agregado[:pending_main_value]).to eq(BigDecimal('-200.00'))
      expect(agregado[:remaining_value]).to eq(0)
      expect(parcelas.first[:saldo]).to eq(BigDecimal('200.00'))
      expect(parcelas.first[:pending_value]).to eq(0)
    end

    it 'aceita percentual ACIMA de 100%' do
      expect(agregado[:paid_percent]).to eq(BigDecimal('120.0'))
    end

    it 'fica "Liquidado" porque nada resta' do
      expect(agregado[:state]).to eq('Liquidado')
    end
  end

  # ------------------------------------------------------------------
  # Cenário C — A DIVERGÊNCIA DELIBERADA (tarefa 4.6 / D-45 / D-49)
  # ------------------------------------------------------------------
  describe 'cenário C — as parcelas NÃO cobrem a dívida' do
    let(:parcelas) do
      [parcela(due_date: Date.new(2025, 4, 10), main: '1000.00'),
       parcela(due_date: Date.new(2025, 5, 10), main: '1000.00')]
    end
    let(:agregado) do
      described_class.aggregate(installments: parcelas, payments: [],
                                total_debt: BigDecimal('5000.00'), original_value: BigDecimal('5000.00'),
                                desagio_value: BigDecimal(0), operation_interest_rate: 0.0,
                                today: Date.new(2025, 2, 15))
    end

    it 'grava "Inconsistente" — onde o legado grava "Pago" (D-45)' do
      # **A única mudança de VALOR desta unidade, e ela é deliberada.**
      #
      # Legado, verbatim (`renegotiation.rb:118-123`):
      #   state = installments_main_value < correct_value ? INCONSISTENT : OPEN
      #   state = remaining_value <= 0 ? CLOSED : OPEN     # ← apaga a linha acima
      #
      # A segunda linha reescreve o estado em TODOS os ramos. A extração
      # confirma: com 2.000 lançados contra 5.000 de dívida, o legado grava
      # **"Pago"**. Consequência: os filtros "Inconsistente" e "Sem parcela
      # cadastrada" da tela nunca retornavam nada (D-49 é o par disto no filtro).
      expect(agregado[:state]).to eq('Inconsistente')
      expect(agregado[:installments_main_value]).to be < agregado[:correct_value]
    end

    it 'o resto do agregado continua idêntico ao legado' do
      expect(agregado[:main_value]).to eq(BigDecimal('2000.00'))
      expect(agregado[:remaining_value]).to eq(BigDecimal('2000.00'))
      expect(agregado[:paid_percent]).to eq(0)
      expect(agregado[:due_installments]).to eq(2)
      expect(agregado[:current_value]).to eq(BigDecimal('2000.00'))
      expect(described_class.unposted_value(
               total_debt: BigDecimal('5000.00'),
               installments_main_value_with_interest: agregado[:installments_main_value_with_interest]
             )).to eq(BigDecimal('3000.00'))
    end
  end

  # ------------------------------------------------------------------
  # Cenário D — o VP que SOBRESCREVE "Valor Parcela" (tarefa 4.9 / D-46)
  # ------------------------------------------------------------------
  describe 'cenário D — VP com taxa de 1,5%' do
    let(:parcelas) do
      [parcela(due_date: Date.new(2025, 2, 10), main: '1000.00'),
       parcela(due_date: Date.new(2025, 3, 10), main: '1000.00'),
       parcela(due_date: Date.new(2025, 4, 10), main: '1000.00')]
    end
    let(:agregado) do
      described_class.aggregate(installments: parcelas, payments: [],
                                total_debt: BigDecimal('3000.00'), original_value: BigDecimal('3000.00'),
                                desagio_value: BigDecimal(0), operation_interest_rate: 1.5,
                                today: Date.new(2025, 2, 15))
    end

    it 'calcula o VP e SOBRESCREVE current_installment_value com ele' do
      # A soma de fevereiro é 1.000,00. Depois do VP, os dois campos passam a
      # mostrar 2.912,20 — a coluna "Valor Parcela" da tela deixa de ser a
      # parcela do mês. **É um número que o cliente lê** (D-46, Q-B25).
      expect(described_class.current_installment_value(parcelas, Date.new(2025, 2, 15)))
        .to eq(BigDecimal('1000.00'))
      expect(agregado[:current_value]).to eq(BigDecimal('2912.2'))
      expect(agregado[:current_installment_value]).to eq(BigDecimal('2912.2'))
    end

    it 'o expoente do VP é due_installments, que INCLUI as vencidas' do
      expect(agregado[:due_installments]).to eq(3)
      expect(agregado[:overdue_installments]).to eq(1)
    end
  end

  # ------------------------------------------------------------------
  # Cenário E — a mora dos dois lados (tarefa 4.10 / Q-B26)
  # ------------------------------------------------------------------
  describe 'cenário E — pagamento quase todo em MORA' do
    let(:parcelas) do
      [parcela(due_date: Date.new(2025, 1, 10), main: '1000.00',
               pagamentos: [{ date: Date.new(2025, 3, 1), cm: '0.01', late: '500.00' }])]
    end
    let(:agregado) do
      described_class.aggregate(installments: parcelas, payments: pagamentos_de({ cm: '0.01' }),
                                total_debt: BigDecimal('1000.00'), original_value: BigDecimal('1000.00'),
                                desagio_value: BigDecimal(0), operation_interest_rate: 0.0,
                                today: Date.new(2025, 3, 15))
    end

    it 'a mora NÃO quita a parcela — ela entra dos dois lados e se CANCELA' do
      p = parcelas.first
      expect(p[:installment_total_value]).to eq(BigDecimal('1500.00')) # devido, com mora
      expect(p[:paid_value]).to eq(BigDecimal('500.01'))               # pago, com mora
      # 1500 - 500,01 = 999,99. Ou seja: `pending = principal+juros+CM - pago_sem_mora`.
      expect(p[:pending_value]).to eq(BigDecimal('999.99'))
      expect(p[:is_paid]).to be(false)
    end

    it 'mas DISTORCE o agregado: "R$ Pago" conta a mora e "R$ A Pagar" não' do
      # É este o efeito observável, e é ele que o cliente vê lado a lado na tela.
      expect(agregado[:paid_value]).to eq(BigDecimal('500.01'))
      expect(agregado[:remaining_value]).to eq(BigDecimal('999.99'))
      # E o percentual pago ignora a mora inteira: 0,01 / 1000 = 0%.
      expect(agregado[:paid_percent]).to eq(0)
    end

    it 'conta os dias de atraso do pagamento retroativo' do
      expect(described_class.payment(date: Date.new(2025, 3, 1), due_date: Date.new(2025, 1, 10),
                                     installment_paid_value_with_interest_cm: BigDecimal('0.01'),
                                     late_payment_value: BigDecimal('500.00'))[:days_late]).to eq(50)
    end
  end

  # ------------------------------------------------------------------
  # Cenário F — os ramos de guarda (tarefas 4.3, 4.5, 4.6)
  # ------------------------------------------------------------------
  describe 'cenário F — renegociação SEM parcela' do
    let(:agregado) do
      described_class.aggregate(installments: [], payments: [],
                                total_debt: BigDecimal('1000.00'), original_value: BigDecimal('800.00'),
                                desagio_value: BigDecimal('900.00'), operation_interest_rate: 2.0,
                                today: Date.new(2025, 2, 15))
    end

    it 'não divide por zero — o percentual é 0' do
      expect(agregado[:paid_percent]).to eq(0)
    end

    it 'fica "Sem parcela cadastrada" — o estado que o filtro do legado nunca alcançava (D-49)' do
      expect(agregado[:state]).to eq('Sem parcela cadastrada')
    end

    it 'aceita deságio MAIOR que o valor original, produzindo total negativo' do
      expect(agregado[:total_value_with_desagio]).to eq(BigDecimal('-100.00'))
    end

    it 'não calcula VP quando não resta nada' do
      expect(agregado[:current_value]).to eq(0)
      expect(agregado[:current_installment_value]).to eq(0)
      expect(agregado[:first_due_date]).to be_nil
    end
  end
end
