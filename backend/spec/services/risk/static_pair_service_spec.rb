# frozen_string_literal: true

require 'rails_helper'

# S5 / BE-241 — o par estático do limite.
#
# **O que isso significa, com honestidade: nao ha oraculo.** Estes valores foram
# conferidos contra o **fonte de 2022** — arquivo e linha citados em cada
# cenario —, e nao contra comportamento observado. O golden trava a LEITURA do
# codigo de 2022; ele nao prova que o numero esta certo, prova que nao mudamos o
# que o legado fazia. A DEC-103b manda espelhar, e e isso que esta feito.
#
# **A marca serve de ponteiro:** no dia em que um numero sair estranho, ela diz
# em segundos que a resposta esta no fonte de 2022, e nao numa base de producao
# que nunca teve estes registros.
#
RSpec.describe Risk::StaticPairService do
  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }

  describe 'type WITHOUT pre-billing' do
    it 'opens no operation at all' do
      tipo = create(:risk_operation_type, title: 'Sem par')
      control = create(:risk_control, project: project, company: company, risk_operation_type: tipo)
      expect(control.risk_operations).to be_empty
    end
  end

  describe 'type WITH pre-billing' do
    let(:tipo) { create(:risk_operation_type, :com_pre, title: 'Com par') }
    let(:control) do
      create(:risk_control, project: project, company: company, risk_operation_type: tipo,
                            taxa: 3.75, original_balance: 50_000.00, original_balance_pre: 30_000.00)
    end

    it 'opens exactly two static operations' do
      expect(control.risk_operations.count).to eq(2)
      expect(control.risk_operations.where(is_static: true).count).to eq(2)
    end

    it 'CROSSES the balances correctly — pre gets original_balance_pre' do
      pre = control.risk_operations.joins(:operation_subtype)
                   .find_by(risk_operation_subtypes: { is_pre: true })
      ant = control.risk_operations.joins(:operation_subtype)
                   .find_by(risk_operation_subtypes: { is_pre: false })

      # Gravados negativos (DEC-01).
      expect(pre.original_balance).to eq(-30_000.00)
      expect(ant.original_balance).to eq(-50_000.00)
    end

    it 'copies the rate, zeroes the value and stamps the legacy observation' do
      control.risk_operations.each do |operacao|
        expect(operacao.agreed_rate).to eq(3.75)
        expect(operacao.operation_value).to eq(0)
        expect(operacao.observation).to eq('Criado automaticamente para o limite')
        expect(operacao.movements).to be_empty
      end
    end

    # **Corrigido pela S7, e o número mudou de propósito — leia antes de
    # "consertar" de volta.**
    #
    # Esta asserção dizia `balance == 0`, porque era o que
    # `Risk::StaticPairService` passa no `RiskOperation.new` e porque o model
    # da S5 **ainda não tinha** o `update_values` do legado. Ele é da S7
    # (`BE-265`), e roda no `before_validation` de TODO save: quando não há
    # movimento nenhum, `prev_bal` continua sendo `original_balance` e a
    # última linha da fonte é `self.balance = prev_bal`
    # (`../sfg/app/models/risk_operation.rb:110`).
    #
    # Ou seja: **no legado o par estático nasce com `balance = original_balance`,
    # não com zero** — o `balance: 0` do `create` é sobrescrito pelo callback
    # antes do INSERT. O `0` da S5 era o valor de entrada, não o resultado.
    #
    # Isto **não muda número nenhum do painel**: `balance` é cache do último
    # movimento e o motor de exposição lê `Risk::Calculator#balance_on`, que
    # continua devolvendo **0** para operação sem movimento (golden `L2`) — a
    # asserção logo abaixo prova as duas coisas juntas.
    #
    # ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b. Fonte: `risk_operation.rb:98-111`.
    it 'nasce com balance = original_balance (S7/BE-265), e balance_on continua 0' do
      control.risk_operations.each do |operacao|
        expect(operacao.balance).to eq(operacao.original_balance)
        expect(operacao.balance_on(Date.current)).to eq(0)
      end
    end

    it 'links the pair in both directions' do
      a, b = control.risk_operations.to_a
      expect(a.pair_id).to eq(b.id)
      expect(b.pair_id).to eq(a.id)
    end

    it 'gives the pair the SUBTYPE title, like the legacy' do
      titulos = control.risk_operations.map(&:title).sort
      expect(titulos).to eq(tipo.subtypes.map(&:title).sort)
    end
  end

  describe 'transactionality — the control is NOT saved when the pair cannot be opened' do
    it 'rolls the whole create back when the type has no pre subtype' do
      tipo = create(:risk_operation_type, :com_pre, title: 'Quebrado')
      # Simula um catálogo corrompido: o subtipo "pré" some.
      tipo.subtypes.find_by(is_pre: true).delete

      antes = RiskControl.count
      expect do
        create(:risk_control, project: project, company: company, risk_operation_type: tipo)
      end.to raise_error(described_class::IncompleteSubtypes)

      # A transação voltou atrás: o limite NÃO existe.
      expect(RiskControl.count).to eq(antes)
    end

    it 'names the type in the business error, instead of a NoMethodError on nil' do
      tipo = create(:risk_operation_type, :com_pre, title: 'Tipo Sem Subtipo')
      tipo.subtypes.find_by(is_pre: true).delete

      expect do
        create(:risk_control, project: project, company: company, risk_operation_type: tipo)
      end.to raise_error(described_class::IncompleteSubtypes, /Tipo Sem Subtipo/)
    end
  end
end
