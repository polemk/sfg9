# frozen_string_literal: true

require 'rails_helper'

# S12 / tarefas 6.3 e 6.4 — a carga dos contratos e dos aceites do legado.
RSpec.describe Contracts::LegacyImport do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og, legacy_id: 77) }

  def contrato_legado(legacy_id:, version:, kind: Contract::KIND_TERMS_OF_USE, creator: 77)
    { legacy_id: legacy_id, kind: kind, version: version, title: 'Termos de Uso',
      body: '<p>texto do legado</p>', creator_legacy_id: creator, created_at: 3.years.ago }
  end

  # 6.3 — DB-330
  it 'a `version` do legado é CONGELADA, não renumerada' do
    og
    described_class.call(
      contract_rows: [contrato_legado(legacy_id: 1, version: 4),
                      contrato_legado(legacy_id: 2, version: 9)],
      dry_run: false
    )

    expect(Contract.order(:version).pluck(:version)).to eq([4, 9])
    expect(Contracts::Resolver.current(Contract::KIND_TERMS_OF_USE).version).to eq(9)
  end

  it 'o dry-run reporta AUTORES ÓRFÃOS' do
    relatorio = described_class.call(
      contract_rows: [contrato_legado(legacy_id: 1, version: 1, creator: 999)], dry_run: true
    )
    expect(relatorio.orphan_creators).to eq(1)
  end

  it 'contrato entra SEM autor em vez de não entrar' do
    described_class.call(contract_rows: [contrato_legado(legacy_id: 1, version: 1, creator: 999)],
                         dry_run: false)
    expect(Contract.first.creator_id).to be_nil
  end

  # OPS-332
  it 'tipo fora do catálogo é IGNORADO e REGISTRADO' do
    relatorio = described_class.call(
      contract_rows: [contrato_legado(legacy_id: 1, version: 1, kind: 'Contrato de usuário')],
      dry_run: false
    )
    expect(Contract.count).to eq(0)
    expect(relatorio.errors.first).to include('fora do catálogo')
  end

  # 6.4 — DEC-66
  describe 'aceites existentes (DEC-66)' do
    it 'entram marcados `implicit_legacy`, com a data original preservada' do
      og
      usuario = create(:user, :colaborador, legacy_id: 500)
      described_class.call(contract_rows: [contrato_legado(legacy_id: 1, version: 1)], dry_run: false)

      data = 2.years.ago
      described_class.call(
        deal_rows: [{ legacy_id: 5, contract_legacy_id: 1, user_legacy_id: 500, created_at: data }],
        dry_run: false
      )

      deal = ContractDeal.last
      expect(deal.source).to eq('implicit_legacy')
      expect(deal.accepted_at).to be_within(1.second).of(data)
      expect(deal.legacy_accepted_at).to be_within(1.second).of(data)
      expect(deal.user_id).to eq(usuario.id)
    end

    it 'NÃO ganham hash inventado — inventá-lo faria carimbo parecer prova de leitura' do
      og
      create(:user, :colaborador, legacy_id: 500)
      described_class.call(contract_rows: [contrato_legado(legacy_id: 1, version: 1)], dry_run: false)
      described_class.call(
        deal_rows: [{ legacy_id: 5, contract_legacy_id: 1, user_legacy_id: 500, created_at: 2.years.ago }],
        dry_run: false
      )

      expect(ContractDeal.last.content_hash).to be_nil
      expect(ContractDeal.last.accepted_body).to be_nil
    end

    it 'e o NOVO aceite explícito continua sendo exigido na próxima entrada' do
      og
      usuario = create(:user, :colaborador, legacy_id: 500)
      described_class.call(contract_rows: [contrato_legado(legacy_id: 1, version: 1)], dry_run: false)
      described_class.call(
        deal_rows: [{ legacy_id: 5, contract_legacy_id: 1, user_legacy_id: 500, created_at: 2.years.ago }],
        dry_run: false
      )

      pendentes = Contracts::PendingService.call(usuario)
      expect(pendentes.map { |p| p[:kind] }).to eq([Contract::KIND_TERMS_OF_USE])
    end
  end
end
