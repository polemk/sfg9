# frozen_string_literal: true

# S5 — **os cenários golden do motor de exposição**.
#
# Os quatro cenários (`L1`..`L4`) estão descritos em
# `openspec/changes/s5-limites-risco/design.md` §4 e os valores esperados foram
# derivados da leitura direta da fonte legada — **o legado não tem uma única
# suíte de testes** (D-114), então não há de onde extrair. Cada valor abaixo é
# reproduzível a partir das linhas citadas no `design.md`.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115
#
# O esquema tipado de risco está entre as **24 migrations que nunca subiram**
# (`analise-dump-producao.md` §1): o dump de produção não tem uma única
# operação, um único movimento nem um único limite tipado. Estes cenários têm
# **fonte** (`../sfg/app/models/risk_operation.rb:104` e `:39-52`), **não
# oráculo** — e por isso nada aqui promove ID a `verified` (DEC-115).
#
# ### Por que os saldos dos movimentos são calculados aqui
#
# O recálculo da cadeia (`RiskOperation#update_values`, BE-265) é da **S7**.
# Estes helpers aplicam a fórmula do legado explicitamente
# (`prev + credit_type_value × movement_value`,
# `../sfg/app/models/risk_operation.rb:104`) para montar a cadeia. Quando a S7
# implementar o recálculo, ele **tem** de produzir estes mesmos saldos — os
# goldens de `L1` são o contrato entre as duas fatias.
module RiskScenarios
  MOVIMENTO_LIBERACAO = 'Liberação do Recurso'
  MOVIMENTO_JUROS = 'Juros'
  MOVIMENTO_LIQUIDACAO = 'Liquidação'

  # Cria os movimentos na ordem dada.
  #
  # `entradas` = `[{ date:, type:, value: }]`, com `type` sendo um
  # `RiskMovementType`.
  #
  # ### O que mudou quando a S7 chegou — leia antes de reescrever
  #
  # Este helper **calculava o saldo de cada movimento à mão**, aplicando
  # `prev + credit_type_value × movement_value` (`risk_operation.rb:104`),
  # porque o recálculo da cadeia (`BE-265`) era da S7 e ainda não existia. O
  # cabeçalho deste arquivo já dizia: *"quando a S7 implementar o recálculo, ele
  # TEM de produzir estes mesmos saldos — os goldens de L1 são o contrato entre
  # as duas fatias."*
  #
  # A S7 implementou, o contrato foi conferido, e agora o cálculo à mão sairia
  # **duas vezes**: o `after_commit` do movimento salva a operação, cujo
  # `before_validation` reescreve `balance` e `sequence` de toda a cadeia. Quem
  # manda agora é `Risk::Calculator.recalculate_chain` — que é o ponto do
  # contrato C2: uma implementação, não duas.
  def encadear_movimentos!(operacao, entradas)
    entradas.map do |entrada|
      RiskMovement.create!(
        risk_operation: operacao,
        movement_type: entrada[:type],
        date: entrada[:date],
        movement_value: entrada[:value],
        balance: 0
      )
    end
  end

  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/risk_operation.rb:104`
  # (a cadeia) e `:39-52` (o sinal do movimento).
  # **Cenário L1** — tipo SEM pré-faturamento.
  #
  # Limite 200.000,00 · taxa 2,55. Uma operação: capital 100.000,00, saldo
  # inicial informado 100.000,00 (gravado −100.000,00), emissão 01/03/2026,
  # vencimento 30/06/2026, e três movimentos.
  #
  # Devolve `{ control:, operation:, project:, company:, carrier: }`.
  def cenario_l1
    tipo = create(:risk_operation_type, title: 'L1 sem pré')
    control = create(:risk_control, risk_operation_type: tipo, limite: 200_000.00, taxa: 2.55)

    operacao = create(:risk_operation,
                      risk_control: control,
                      operation_value: 100_000.00,
                      original_balance: 100_000.00,
                      issue_date: Date.new(2026, 3, 1),
                      due_date: Date.new(2026, 6, 30))

    # **O primeiro movimento não é mais criado aqui.** A S7 trouxe o
    # `after_create` de `RiskOperation` (`BE-264`,
    # `../sfg/app/models/risk_operation.rb:39-52`): tipo SEM pré-faturamento
    # nasce com "Liberação do Recurso" de `operation_value` na data de emissão,
    # resolvido por `integration_key` (B-09). Criá-lo à mão aqui produziria a
    # liberação **em dobro** — e os saldos golden mudariam.
    #
    # O tipo semeado tem `credit_type = 'D'` (+1), o mesmo sinal do "L1 débito"
    # que este helper usava. A cadeia continua sendo:
    # 0,00 → 2.500,00 → −27.500,00.
    debito = create(:risk_movement_type, :debito, title: 'L1 débito')
    credito = create(:risk_movement_type, :credito, title: 'L1 crédito')

    encadear_movimentos!(operacao, [
                           { date: Date.new(2026, 3, 15), type: debito,  value: 2_500.00 },
                           { date: Date.new(2026, 4, 20), type: credito, value: 30_000.00 }
                         ])

    { control: control.reload, operation: operacao.reload, type: tipo,
      project: control.project, company: control.company, carrier: control.carrier }
  end

  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/risk_control.rb:18-64`
  # (o `after_create` do par estático).
  # **Cenário L2** — tipo COM pré-faturamento.
  #
  # Limite criado com saldo inicial liquidável 50.000,00 e pré 30.000,00. O
  # `after_create` abre as duas operações estáticas, **sem movimento**.
  def cenario_l2
    tipo = create(:risk_operation_type, :com_pre, title: 'L2 com pré')
    control = create(:risk_control,
                     risk_operation_type: tipo,
                     limite: 200_000.00, taxa: 2.55,
                     original_balance: 50_000.00,
                     original_balance_pre: 30_000.00)

    estaticas = control.risk_operations.where(is_static: true).to_a
    {
      control: control.reload, type: tipo,
      project: control.project, company: control.company, carrier: control.carrier,
      pre: estaticas.find { |op| op.operation_subtype.is_pre? },
      antecipacao: estaticas.find { |op| !op.operation_subtype.is_pre? }
    }
  end
end

RSpec.configure do |config|
  config.include RiskScenarios
end
