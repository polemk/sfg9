# frozen_string_literal: true

require 'rails_helper'

# S7 / **BE-261..BE-268** — a cascata de callbacks do model, e as validações que
# **continuam ausentes de propósito**.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `create_risk_operations` está entre as **24 migrations que nunca subiram**
# (`analise-dump-producao.md` §1). Fonte destes exemplos:
# `../sfg/app/models/risk_operation.rb:20-62`. **Fonte, não oráculo.**
RSpec.describe RiskOperation do
  before { semear_tipos_de_movimento! }

  let(:autor) { create(:user) }
  let(:tipo) { create(:risk_operation_type, title: 'Model S7') }
  let!(:limite) { create(:risk_control, risk_operation_type: tipo, limite: 500_000, taxa: 2.0) }

  def nova(**attrs)
    RiskOperation.new({
      project: limite.project, company: limite.company, carrier: limite.carrier,
      operation_type: tipo, user_id: autor.id,
      issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 6, 30),
      operation_value: 10_000, original_balance: 10_000
    }.merge(attrs))
  end

  # =====================================================================
  # BE-261 — a quádrupla
  # =====================================================================
  describe 'resolução do limite pela quádrupla (BE-261)' do
    it 'resolve por (projeto, empresa, portador, tipo)' do
      operacao = nova
      operacao.save!
      expect(operacao.risk_control_id).to eq(limite.id)
    end

    it 'NÃO filtra is_active — operação em limite desativado é aceita' do
      # `risk_operation.rb:21` não tem `is_active` no `where`. **Replicado**, e
      # a DEC-105 confirmou o critério do espelho mesmo com consequência
      # visível (457 dos 767 limites entram desativados na carga).
      limite.update!(is_active: false)
      operacao = nova
      expect(operacao.save).to be(true)
      expect(operacao.risk_control_id).to eq(limite.id)
    end

    it 'recusa com mensagem explicativa quando não há limite para a combinação' do
      outro_portador = create(:carrier, title: 'Sem limite')
      operacao = nova(carrier: outro_portador)
      expect(operacao.save).to be(false)
      expect(operacao.errors.full_messages.to_sentence).to include('não existe limite cadastrado')
    end

    it 'carimba original_due_date = due_date SÓ no create' do
      operacao = nova
      operacao.save!
      expect(operacao.original_due_date).to eq(Date.new(2026, 6, 30))

      # Numa edição posterior o carimbo NÃO se move — é o que preserva o
      # histórico de prorrogação.
      operacao.update_columns(due_date: Date.new(2026, 9, 30))
      operacao.reload.update!(title: 'x')
      expect(operacao.reload.original_due_date).to eq(Date.new(2026, 6, 30))
    end

    it 'título vazio cai para o título do portador' do
      operacao = nova(title: nil)
      operacao.save!
      expect(operacao.title).to eq(limite.carrier.title)
    end
  end

  # =====================================================================
  # BE-262 / DEC-67 — tipo ↔ subtipo
  # =====================================================================
  describe 'tipo ↔ subtipo (BE-262 — DEC-67 vence a tarefa 2.2)' do
    it 'sem subtipo informado, usa o PADRÃO do tipo' do
      # A tarefa 2.2 do `tasks.md` mandava **recusar com 422** pedindo escolha
      # explícita (T-D3). A **DEC-67** decidiu depois: o tipo declara
      # `is_default_for_type`, e o padrão semeado **reproduz o que o
      # `subtypes.…pluck(:id).first` sem `order` escolhia** no legado.
      operacao = nova
      operacao.save!
      expect(operacao.operation_subtype_id).to eq(tipo.default_subtype.id)
    end

    it 'em tipo COM pré-faturamento, o padrão é o subtipo "pré" — como o .first do legado' do
      # `risk_operation_type.rb:23` cria o "pré" ANTES do de "antecipação", e
      # o `.first` sem `order` caía nele.
      tipo_pre = create(:risk_operation_type, :com_pre, title: 'Pré model S7')
      controle = create(:risk_control, risk_operation_type: tipo_pre)
      operacao = RiskOperation.new(project: controle.project, company: controle.company,
                                   carrier: controle.carrier, operation_type: tipo_pre,
                                   user_id: autor.id, issue_date: Date.new(2026, 3, 1),
                                   due_date: Date.new(2026, 6, 30), operation_value: 1, original_balance: 0)
      operacao.save!
      expect(operacao.operation_subtype.is_pre).to be(true)
    end

    it 'subtipo informado SOBRESCREVE o tipo (replicado)' do
      outro = create(:risk_operation_type, title: 'Outro model S7')
      create(:risk_control, project: limite.project, company: limite.company,
                            carrier: limite.carrier, risk_operation_type: outro)

      operacao = nova(operation_subtype: outro.default_subtype)
      operacao.save!
      expect(operacao.operation_type_id).to eq(outro.id)
    end

    it 'tipo SEM nenhum subtipo é recusado, com erro explicativo' do
      tipo.subtypes.delete_all
      operacao = nova
      expect(operacao.save).to be(false)
      expect(operacao.errors.full_messages.to_sentence).to include('não tem nenhum subtipo')
    end
  end

  # =====================================================================
  # BE-267 / Q-R7 — as ausências que CONTINUAM ausentes
  # =====================================================================
  describe 'as validações ausentes (BE-267 — Q-R7, "replicar as ausências")' do
    it 'aceita operação de capital ZERO' do
      expect(nova(operation_value: 0).save).to be(true)
    end

    it 'aceita vencimento ANTERIOR à emissão' do
      # Não há `due_date >= issue_date` em `risk_operation.rb:54-62`.
      # Acrescentá-la recusaria dado que hoje entra — é decisão de usuário.
      operacao = nova(issue_date: Date.new(2026, 6, 30), due_date: Date.new(2026, 3, 1))
      expect(operacao.save).to be(true)
    end

    it 'aceita taxa acordada negativa e capital negativo' do
      expect(nova(agreed_rate: -5, operation_value: -1_000).save).to be(true)
    end

    it 'exige empresa, portador, tipo, projeto, usuário, datas e limite' do
      operacao = RiskOperation.new
      operacao.valid?
      %i[company_id carrier_id operation_type_id project_id user_id
         issue_date due_date risk_control_id].each do |campo|
        expect(operacao.errors[campo]).not_to be_empty, "esperava erro em #{campo}"
      end
    end

    it '`operation_value` tem presença declarada mas NUNCA dispara — a coluna tem default 0' do
      # `validates :operation_value, presence: true` está no legado (`:60`) e
      # está aqui. Ele é inalcançável nos dois: a coluna nasce com `default: 0`,
      # então `RiskOperation.new.operation_value` já é `0`, que é presente. É
      # exatamente o "capital zero continua aceito" da Q-R7, por outro caminho.
      expect(RiskOperation.new.operation_value).to eq(0)
      operacao = RiskOperation.new
      operacao.valid?
      expect(operacao.errors[:operation_value]).to be_empty
    end
  end

  # =====================================================================
  # BE-268 / T-D4 / DEC-35 — `is_ended` é RÓTULO
  # =====================================================================
  describe 'is_ended é rótulo, e as TRÊS não-consequências (BE-268 / DEC-35)' do
    let(:operacao) { nova.tap(&:save!) }

    before { operacao.update!(is_ended: true) }

    it '(1) NÃO bloqueia movimento' do
      movimento = RiskMovement.create(risk_operation: operacao, movement_type: tipo_de_movimento('juros'),
                                      date: Date.new(2026, 4, 1), movement_value: 100, balance: 0,
                                      user_id: autor.id)
      expect(movimento).to be_persisted
    end

    it '(2) NÃO bloqueia prorrogação' do
      resultado = Risk::ExtensionService.create(project: limite.project, operation_id: operacao.id,
                                                attrs: { new_due_date: Date.new(2026, 8, 31) }, actor: autor)
      expect(resultado[:status]).to eq(201)
    end

    it '(3) NÃO retira a operação de operations_on — a exposição continua contando' do
      # **Fora de qualquer default**: retirar a encerrada de `operations_on`
      # mudaria a exposição do histórico inteiro. DEC-35 é explícita.
      expect(Risk::Calculator.operations_on(limite, Date.new(2026, 4, 1))).to include(operacao)
    end

    it 'e continua FATURÁVEL (available_for_receipt)' do
      expect(RiskOperation.available_for_receipt).to include(operacao)
    end
  end

  # =====================================================================
  # Escopo C1
  # =====================================================================
  describe 'contrato C1' do
    it 'declara for_project e NÃO usa default_scope' do
      expect(described_class).to be_project_scoped
      expect(described_class.default_scopes).to be_empty
    end
  end
end
