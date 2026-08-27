# frozen_string_literal: true

require 'rails_helper'

# S7 / **OPS-238, DB-239** — o **contrato executável** entre o borderô (S6) e a
# exposição ao risco (S7).
#
# ## Quem constrói o quê (contrato C4 — um dono por ID)
#
# A **implementação** é da S6 e vive em
# `app/services/receivables/risk_sync_service.rb`. **Este arquivo é o contrato**:
# ele descreve, executando, o que a S7 exige que aquele serviço faça, para que
# uma mudança de qualquer um dos dois lados apareça aqui e não em produção.
# É a "Regra de fronteira" de `ai9-conventions.md` aplicada a duas fatias.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `add_risk_operation_type_to_receivable_entries` está entre as **24 migrations
# que nunca subiram** (`analise-dump-producao.md` §1) — conferido no dump: o
# `COPY` de `receivable_entries` tem 68 colunas e **nenhuma das duas**
# (`risk_operation_type_id`, `risk_operation_subtype_id`) está lá.
#
# Ou seja: em três anos de produção **nenhum borderô jamais gerou operação de
# risco**. O `after_commit` de `../sfg/app/models/receivable_entry.rb:124-176` é
# código de 2022 que nunca rodou. Fonte, não oráculo.
RSpec.describe 'Contrato borderô → risco (OPS-238)' do
  before { semear_tipos_de_movimento! }

  let(:autor) { create(:user) }

  # ---------------------------------------------------------------------
  # Ramo 1 — tipo SEM pré-faturamento: cria (ou revincula) a operação
  # ---------------------------------------------------------------------
  describe 'tipo SEM pré-faturamento — cria a operação do recebível' do
    let(:tipo) { create(:risk_operation_type, title: 'Liq contrato S7') }
    let!(:limite) { create(:risk_control, risk_operation_type: tipo, limite: 900_000, taxa: 2.0) }

    let(:entry) do
      build(:receivable_entry,
            project: limite.project, company: limite.company, carrier: limite.carrier,
            author: autor, date: Date.new(2026, 3, 1), data_credito: Date.new(2026, 5, 30),
            nro_bordero: '4711', nominal_tax: 1.75,
            risk_operation_type_id: tipo.id, risk_operation_subtype_id: tipo.default_subtype.id,
            valor_bruto: 120_000, valor_liquido: 118_500)
    end

    it 'cria a operação com o LÍQUIDO, a data de crédito e a taxa nominal' do
      entry.save!(validate: false)
      Receivables::RiskSyncService.call!(entry)

      operacao = entry.reload.risk_operation
      expect(operacao).to be_present
      expect(operacao.title).to eq('Operação do recebível #4711')
      expect(operacao.operation_value).to eq(118_500)
      expect(operacao.issue_date).to eq(Date.new(2026, 3, 1))
      expect(operacao.due_date).to eq(Date.new(2026, 5, 30))
      expect(operacao.agreed_rate).to eq(1.75)
      expect(operacao.contract_number).to eq('4711')
      expect(operacao.risk_control_id).to eq(limite.id)
    end

    it 'a operação criada pelo borderô ganha o movimento de liberação (BE-264)' do
      # É a costura entre as duas fatias: o `after_create` da S7 dispara no
      # `RiskOperation.create!` da S6, sem que a S6 precise saber dele.
      entry.save!(validate: false)
      Receivables::RiskSyncService.call!(entry)

      operacao = entry.reload.risk_operation
      expect(operacao.movements.count).to eq(1)
      expect(operacao.movements.first.movement_type.integration_key).to eq(RiskMovementType::RELEASE_KEY)
      expect(operacao.movements.first.movement_value).to eq(118_500)
      expect(operacao.balance).to eq(118_500)
    end

    it 'sem limite ATIVO para a combinação, recusa com "não tem limite"' do
      limite.update!(is_active: false)
      entry.save!(validate: false)

      expect { Receivables::RiskSyncService.call!(entry) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(RiskOperation.where(receivable_id: entry.id)).to be_empty
    end

    it 'na segunda chamada REVINCULA em vez de criar outra' do
      entry.save!(validate: false)
      Receivables::RiskSyncService.call!(entry)
      primeira = entry.reload.risk_operation

      Receivables::RiskSyncService.call!(entry.reload)
      expect(entry.reload.risk_operation.id).to eq(primeira.id)
      expect(RiskOperation.where(receivable_id: entry.id).count).to eq(1)
    end

    it 'DB-239 — apagar o borderô apaga a operação junto (dependent: :destroy)' do
      entry.save!(validate: false)
      Receivables::RiskSyncService.call!(entry)
      operacao_id = entry.reload.risk_operation.id

      entry.destroy!
      expect(RiskOperation.exists?(operacao_id)).to be(false)
    end
  end

  # ---------------------------------------------------------------------
  # Ramo 2 — tipo COM pré-faturamento: libera recurso na operação ESTÁTICA
  # ---------------------------------------------------------------------
  describe 'tipo COM pré-faturamento — libera recurso na operação estática' do
    let(:tipo) { create(:risk_operation_type, :com_pre, title: 'Pré contrato S7') }
    let!(:limite) { create(:risk_control, risk_operation_type: tipo, limite: 900_000, taxa: 2.0) }
    let(:subtipo_pre) { tipo.subtypes.find_by(is_pre: true) }

    let(:entry) do
      build(:receivable_entry,
            project: limite.project, company: limite.company, carrier: limite.carrier,
            author: autor, date: Date.new(2026, 3, 1), data_credito: Date.new(2026, 5, 30),
            nro_bordero: '4712', nominal_tax: 1.0,
            risk_operation_type_id: tipo.id, risk_operation_subtype_id: subtipo_pre.id,
            valor_bruto: 60_000, valor_liquido: 59_000)
    end

    it 'NÃO abre operação nova — lança "Liberação do Recurso" na estática' do
      entry.save!(validate: false)
      estatica = limite.risk_operations.find_by(operation_subtype_id: subtipo_pre.id)
      expect(estatica).to be_present

      expect { Receivables::RiskSyncService.call!(entry) }
        .not_to(change { RiskOperation.count })

      movimento = estatica.reload.movements.sole
      expect(movimento.movement_type.integration_key).to eq(RiskMovementType::RELEASE_KEY)
      expect(movimento.movement_value).to eq(59_000)
      expect(movimento.date).to eq(Date.new(2026, 3, 1))
    end

    it 'o saldo da estática passa a refletir a liberação (cadeia da S7)' do
      entry.save!(validate: false)
      Receivables::RiskSyncService.call!(entry)

      estatica = limite.risk_operations.find_by(operation_subtype_id: subtipo_pre.id).reload
      # A estática nasce com `original_balance = 0` nesta factory, e o débito
      # de 59.000 é `+1` — o saldo é o acumulado.
      expect(estatica.balance).to eq(59_000)
      expect(estatica.balance_on(Date.new(2026, 3, 1))).to eq(59_000)
    end

    it 'operação estática ausente FALHA com erro, em vez de seguir em silêncio' do
      RiskOperation.where(risk_control_id: limite.id).delete_all
      entry.save!(validate: false)

      expect { Receivables::RiskSyncService.call!(entry) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  # ---------------------------------------------------------------------
  # DB-239 — o outro lado do contrato
  # ---------------------------------------------------------------------
  describe 'DB-239 — o contrato de fronteira, nos dois sentidos' do
    it 'ReceivableEntry has_one :risk_operation e RiskOperation belongs_to :receivable' do
      expect(ReceivableEntry.reflect_on_association(:risk_operation).macro).to eq(:has_one)
      expect(ReceivableEntry.reflect_on_association(:risk_operation).options[:dependent]).to eq(:destroy)
      expect(RiskOperation.reflect_on_association(:receivable).macro).to eq(:belongs_to)
    end

    it 'RiskOperation has_one :receipt com restrict_with_error, e o escopo available_for_receipt' do
      # **Handshake com a S8** (tarefa 11.6): a `RiskOperation` é a
      # `operation_class` da classe LIQ de remuneração.
      expect(RiskOperation.reflect_on_association(:receipt).options[:dependent]).to eq(:restrict_with_error)
      expect(Receipt::KIND_BY_OPERATION['RiskOperation']).to eq(Receipt::KIND_RISK)
      expect(RiskOperation.available_for_receipt.to_sql).to include('receipt_id')
    end
  end
end
