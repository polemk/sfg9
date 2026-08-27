# frozen_string_literal: true

# S7 — **os cenários golden das operações de risco** (`M1`..`M5`).
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# Seis migrations desta família estão entre as **24 que nunca subiram**
# (`analise-dump-producao.md` §1): `create_risk_operation_types`,
# `create_risk_movement_types`, `create_risk_operations`,
# `create_risk_movements`, `create_risk_operation_extensions` e
# `create_risk_operation_subtypes`. A última migration aplicada em produção é de
# **25/05/2022** e o sistema rodou em uso até **31/05/2025** — ou seja, em três
# anos **nenhuma operação de risco tipada, nenhum movimento e nenhuma
# prorrogação existiram**.
#
# **Portanto estes goldens têm uma FONTE, não um ORÁCULO.** Cada valor abaixo é
# reproduzível a partir das linhas citadas do legado; nenhum foi conferido
# contra dado real, porque não há dado real a conferir. O teste prova que **não
# mudamos o que o código de 2022 fazia** — não prova que o número está certo.
#
# É a diferença desta fatia para a **S6**, que teve o dump como oráculo (28.099
# linhas × 33 colunas de borderô, zero divergência). Aqui esse recurso não
# existe, e dizer isso é parte do trabalho.
#
# **A marca serve de ponteiro:** no dia em que um número sair estranho em
# produção, ela distingue em segundos "isto sempre foi assim e foi validado" de
# "isto nunca rodou e pode ser defeito de 2022 que herdamos de propósito".
module RiskOperationScenarios
  FONTE_CADEIA = '../sfg/app/models/risk_operation.rb:98-111'
  FONTE_SINAL = '../sfg/app/models/risk_movement_type.rb:53-61'

  # Garante os oito tipos de movimentação de referência (OPS-231). Os três
  # funcionais (`liberacao_do_recurso`, `valor_transferido`,
  # `transferencia_recebida`) são **contrato** com esta fatia.
  def semear_tipos_de_movimento!
    return if RiskMovementType.exists?(integration_key: RiskMovementType::RELEASE_KEY)

    Seeds::Reference::RiskMovementTypes.call!
  end

  def tipo_de_movimento(chave)
    semear_tipos_de_movimento!
    RiskMovementType.find_by!(integration_key: chave)
  end

  # ---------------------------------------------------------------------
  # Cenário M1 — a cadeia de saldos (BE-265)
  # ---------------------------------------------------------------------
  # Tipo **sem** pré-faturamento. Capital 100.000,00; saldo inicial informado
  # 100.000,00 (gravado **−100.000,00**, `risk_operation.rb:34`); emissão
  # 01/03/2026; vencimento 30/06/2026.
  #
  # | # | Data | Tipo | credit_type | sinal | Valor | balance | sequence |
  # | - | ---- | ---- | ----------- | ----- | ----- | ------- | -------- |
  # | 1 | 01/03/2026 | Liberação do Recurso | D | +1 | 100.000,00 | **0,00** | 1 |
  # | 2 | 15/03/2026 | Juros | D | +1 | 2.500,00 | **2.500,00** | 2 |
  # | 3 | 20/04/2026 | Liquidação | C | −1 | 30.000,00 | **−27.500,00** | 3 |
  #
  # `risk_operations.balance` = **−27.500,00**.
  #
  # O movimento 1 **não é criado aqui**: ele nasce do `after_create` de
  # `RiskOperation` (BE-264). Criá-lo à mão esconderia o dia em que o callback
  # parasse de rodar.
  def cenario_m1(user: nil)
    semear_tipos_de_movimento!
    autor = user || create(:user)
    tipo = create(:risk_operation_type, title: 'M1 sem pré')
    control = create(:risk_control, risk_operation_type: tipo, limite: 200_000.00, taxa: 2.55)

    operacao = create(:risk_operation,
                      author: autor,
                      risk_control: control,
                      title: 'Operação M1',
                      operation_value: 100_000.00,
                      original_balance: 100_000.00,
                      issue_date: Date.new(2026, 3, 1),
                      due_date: Date.new(2026, 6, 30))

    juros = RiskMovement.create!(risk_operation: operacao, movement_type: tipo_de_movimento('juros'),
                                 date: Date.new(2026, 3, 15), movement_value: 2_500.00,
                                 balance: 0, user_id: autor.id)
    liquidacao = RiskMovement.create!(risk_operation: operacao, movement_type: tipo_de_movimento('liquidacao'),
                                      date: Date.new(2026, 4, 20), movement_value: 30_000.00,
                                      balance: 0, user_id: autor.id)

    { control: control.reload, operation: operacao.reload, type: tipo, user: autor,
      liberacao: operacao.movements.order(:sequence).first,
      juros: juros.reload, liquidacao: liquidacao.reload,
      project: control.project, company: control.company, carrier: control.carrier }
  end

  # ---------------------------------------------------------------------
  # Cenário M2 — transferência pré ↔ antecipação (BE-275)
  # ---------------------------------------------------------------------
  # Limite de tipo **com** pré-faturamento: a S5 abre o par estático, ambos com
  # `balance_on = 0` e **sem movimento**.
  def cenario_m2(user: nil)
    semear_tipos_de_movimento!
    autor = user || create(:user)
    tipo = create(:risk_operation_type, :com_pre, title: 'M2 com pré')
    control = create(:risk_control, risk_operation_type: tipo, limite: 500_000.00, taxa: 3.0,
                                    original_balance: 0, original_balance_pre: 0)

    estaticas = control.risk_operations.where(is_static: true).to_a
    {
      control: control.reload, type: tipo, user: autor,
      project: control.project, company: control.company, carrier: control.carrier,
      pre: estaticas.find { |op| op.operation_subtype.is_pre? },
      antecipacao: estaticas.find { |op| !op.operation_subtype.is_pre? }
    }
  end
end

RSpec.configure do |config|
  config.include RiskOperationScenarios
end
