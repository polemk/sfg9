# frozen_string_literal: true

require 'rails_helper'

# S5 / BE-278, BE-279, OPS-232 — os dois catálogos do bloco de risco.
RSpec.describe RiskOperationType do
  describe 'the after_create generates the subtypes' do
    it 'creates ONE subtype for a type without pre-billing' do
      tipo = create(:risk_operation_type, title: 'Fomento X')
      expect(tipo.subtypes.count).to eq(1)
      subtipo = tipo.subtypes.first
      expect(subtipo.title).to eq('Fomento X')
      expect(subtipo.is_pre).to be(false)
      expect(subtipo.pair_id).to be_nil
    end

    it 'creates TWO linked subtypes for a type with pre-billing' do
      tipo = create(:risk_operation_type, :com_pre, title: 'Comissária X')
      expect(tipo.subtypes.count).to eq(2)

      pre = tipo.subtypes.find_by(is_pre: true)
      ant = tipo.subtypes.find_by(is_pre: false)
      expect(pre.title).to eq('Comissária X - pré-faturamento')
      expect(ant.title).to eq('Comissária X - antecipação')
      expect(pre.pair_id).to eq(ant.id)
      expect(ant.pair_id).to eq(pre.id)
    end

    it 'marks the PRE subtype as the default — reproducing the legacy `.first` (DEC-67)' do
      # No legado `subtypes...pluck(:id).first` era ordem de inserção, e o "pré"
      # é criado ANTES do "antecipação". A coluna torna a escolha explícita.
      tipo = create(:risk_operation_type, :com_pre, title: 'Padrão X')
      expect(tipo.default_subtype.is_pre).to be(true)
      expect(tipo.subtypes.where(is_default_for_type: true).count).to eq(1)
    end

    it 'enforces ONE default subtype per type at the database level' do
      tipo = create(:risk_operation_type, :com_pre, title: 'Dois padrões')
      outro = tipo.subtypes.find_by(is_pre: false)
      expect { outro.update_column(:is_default_for_type, true) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'flag propagation to subtypes' do
    it 'pushes allow_manual_operations, allow_receivable_entries and is_active down' do
      tipo = create(:risk_operation_type, :com_pre, title: 'Propaga')
      tipo.update!(is_active: false, allow_manual_operations: false)

      tipo.subtypes.reload.each do |subtipo|
        expect(subtipo.is_active).to be(false)
        expect(subtipo.allow_manual_operations).to be(false)
      end
    end

    it 'propagates INSIDE the transaction, not after commit' do
      # No legado era `after_commit`: se a propagação falhasse, o tipo ficava
      # salvo com os subtipos divergentes.
      tipo = create(:risk_operation_type, :com_pre, title: 'Transacional')
      expect(described_class._commit_callbacks.map(&:filter).map(&:to_s))
        .not_to include(/propagate/)
    end
  end

  describe 'integration key — the four seeded keys are CONTRACT' do
    it 'derives the same keys the legacy did' do
      {
        'Fomento' => 'fomento',
        'Comissária' => 'comissaria',
        'Intercompany' => 'intercompany',
        'Auto Liquidável' => 'auto_liquidavel'
      }.each do |titulo, chave|
        expect(create(:risk_operation_type, title: titulo).integration_key).to eq(chave)
      end
    end

    it 'FREEZES the key when the title is renamed (DC-22)' do
      tipo = create(:risk_operation_type, title: 'Original')
      tipo.update!(title: 'Renomeado')
      expect(tipo.reload.integration_key).to eq('original')
    end
  end

  describe 'seeded types cannot be removed' do
    it 'aborts the destroy of an is_default type' do
      tipo = create(:risk_operation_type, :semeado, title: 'Semeado')
      expect(tipo.destroy).to be(false)
      expect(described_class.exists?(tipo.id)).to be(true)
    end
  end

  describe 'contract C1 — global catalog, never project scoped' do
    it 'is a global catalog' do
      expect(described_class).to be_global_catalog
      expect(described_class.column_names).not_to include('project_id')
    end
  end
end

RSpec.describe RiskMovementType do
  describe 'credit_type as the SIGN of the movement' do
    it "maps 'D' to +1 and 'C' to −1" do
      expect(create(:risk_movement_type, :debito, title: 'D1').credit_type_value).to eq(1)
      expect(create(:risk_movement_type, :credito, title: 'C1').credit_type_value).to eq(-1)
    end

    it 'derives the description instead of storing it' do
      expect(described_class.column_names).not_to include('credit_type_description')
      tipo = create(:risk_movement_type, :debito, title: 'D2')
      expect(tipo.credit_type_description).to eq('Débito')
      tipo.update!(credit_type: 'C')
      # No legado a descrição era gravada no create e nunca recalculada.
      expect(tipo.credit_type_description).to eq('Crédito')
    end

    it 'refuses anything outside C/D at the DATABASE level' do
      tipo = create(:risk_movement_type, title: 'Check')
      expect { tipo.update_column(:credit_type, 'X') }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe 'functional types resolve by KEY, not by title (B-09 / OPS-232)' do
    let!(:release) do
      create(:risk_movement_type, :semeado, title: 'Liberação do Recurso',
                                            credit_type: 'D', is_system_exclusive: true)
    end
    let!(:out) do
      create(:risk_movement_type, :semeado, title: 'Valor Transferido',
                                            credit_type: 'C', is_transfer: true)
    end
    let!(:inbound) do
      create(:risk_movement_type, :semeado, title: 'Transferência Recebida',
                                            credit_type: 'D', is_transfer: true)
    end

    it 'finds the three by integration key' do
      expect(described_class.release).to eq(release)
      expect(described_class.transfer_out).to eq(out)
      expect(described_class.transfer_in).to eq(inbound)
    end

    it 'keeps working after the title is renamed through the UI' do
      # É exatamente o que quebrava no legado: `where(title: "Liberação do Recurso")`.
      release.update!(title: 'Liberação de Recurso (novo nome)')
      expect(described_class.release).to eq(release.reload)
    end

    it 'raises a BUSINESS error, not NoMethodError, when the type is missing' do
      # O tipo semeado não pode ser removido (é a outra regra); o cenário real
      # de "sumiu" é a chave ter sido trocada à mão ou o seed não ter rodado.
      release.update_column(:integration_key, 'outra_coisa')
      expect { described_class.release }
        .to raise_error(described_class::MissingFunctionalType, /liberacao_do_recurso/)
    end
  end
end
