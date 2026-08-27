# frozen_string_literal: true

require 'rails_helper'

# S5 / DB-240, OPS-236 — **a expansão dos limites do formato pré-2022**.
#
# Este é o caminho de carga que de fato importa: o dump de produção mostra que
# **as 600 linhas de `risk_controls` estão TODAS no formato antigo**, com os 4
# pares fixos `(limite_X, taxa_X)` e sem coluna de tipo — a migration
# `change_risk_control_fields` nunca subiu
# (`.migration-ai9/analise-dump-producao.md` §2, consulta 5).
#
# **NUNCA EXECUTADO EM PRODUÇÃO** —
# `generate_new_controls_on_migration` (`../sfg/app/models/risk_control.rb:172-210`)
# faz parte do bloco de 2022 que nunca subiu.
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
# As duas únicas coisas não espelhadas têm DEC própria mandando: `destroy_all`
# das posições diárias (**DEC-57** manda preservar — são 642.447 linhas) e o
# casamento de tipo por título literal (**B-09** já o trocou por chave em todo o
# bloco, com o mesmo de-para).
RSpec.describe Sfg::Etl::Converters::RiskControls do
  before { Seeds::Reference::RiskOperationTypes.call! }

  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }
  let(:carrier) { create(:carrier, title: 'Portador Herdado') }

  # A linha como ela chega do legado: sem tipo, com os 4 pares.
  def limite_herdado(valores)
    ProjectToCarrierConnection.find_or_create_by!(project: project, carrier: carrier)
    RiskControl.create!(
      { project: project, company: company, carrier: carrier,
        risk_operation_type_id: nil, legacy_id: 4_242, is_active: true }.merge(valores)
    )
  end

  describe 'the inherited row itself' do
    it 'is accepted WITHOUT a type when it carries a legacy_id' do
      herdado = limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)
      expect(herdado).to be_persisted
      expect(herdado).to be_legacy_shape
    end

    it 'is REFUSED without a type when it was created by the application' do
      # O nulo é para a linha herdada, não é porta aberta para a tela.
      novo = build(:risk_control, project: project, company: company,
                                  carrier: carrier, risk_operation_type: nil)
      expect(novo).not_to be_valid
      expect(novo.errors[:risk_operation_type_id]).to be_present
    end

    it 'stays OUT of every aggregate — that is what the "Legado" label announces' do
      limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)

      resumo = Risk::AggregateService.total_limits_on(company, Date.current)
      expect(resumo[:limits].map { |l| l[:total] }).to all(eq(0))
      expect(Risk::AggregateService.controls_info_on(company, Date.current)).to be_empty
    end

    it 'answers ZERO to a direct call of the engine, instead of blowing up on nil' do
      herdado = limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)

      expect(Risk::Calculator.limite_utilizado_on(herdado)).to eq(0)
      expect(Risk::Calculator.limite_liquidavel_on(herdado)).to eq(0)
      expect(Risk::Calculator.limite_pre_on(herdado)).to eq(0)
      expect(Risk::Calculator.limite_disponivel_on(herdado)).to eq(0.0)
    end
  end

  describe '.expand_typed_controls!' do
    it 'creates FOUR typed controls per source row — one per type, ALWAYS' do
      # NUNCA EXECUTADO EM PRODUÇÃO · `risk_control.rb:174`
      # (`RiskOperationType.all.each`) — a rotina cria uma linha por tipo mesmo
      # com limite e taxa zerados. Espelhado por DEC-103b.
      limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5,
                     limite_comissaria: 300_000, taxa_comissaria: 1.8)

      resultado = described_class.expand_typed_controls!

      expect(resultado[:created]).to eq(4)
      tipados = RiskControl.where.not(risk_operation_type_id: nil)
      expect(tipados.map { |c| c.risk_operation_type.integration_key }.sort)
        .to eq(%w[auto_liquidavel comissaria fomento intercompany])
      expect(tipados.find_by(risk_operation_type: RiskOperationType.find_by(integration_key: 'fomento')).limite)
        .to eq(500_000)
    end

    it 'creates the zeroed families too, with limite and taxa at zero' do
      # NUNCA EXECUTADO EM PRODUÇÃO · `risk_control.rb:174,190-204`
      limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)

      described_class.expand_typed_controls!

      zerado = RiskControl.joins(:risk_operation_type)
                          .find_by(risk_operation_types: { integration_key: 'intercompany' })
      expect(zerado).to be_present
      expect(zerado.limite).to eq(0)
      expect(zerado.taxa).to eq(0)
    end

    it 'carries the pair (limite, taxa) of each family to its own type' do
      # NUNCA EXECUTADO EM PRODUÇÃO · `risk_control.rb:190-204`
      limite_herdado(limite_intercompany: 0, taxa_intercompany: 0.9)

      tipado = nil
      described_class.expand_typed_controls!
      tipado = RiskControl.joins(:risk_operation_type)
                          .find_by(risk_operation_types: { integration_key: 'intercompany' })
      expect(tipado.limite).to eq(0)
      expect(tipado.taxa).to eq(0.9)
    end

    it 'DEACTIVATES only auto_liquidavel, and copies is_active for the other three' do
      # NUNCA EXECUTADO EM PRODUÇÃO · `risk_control.rb:194` (`nrc.is_active = 0`
      # dentro do `when "Auto Liquidável"`). Não há justificativa no código de
      # 2022, e é a família com MAIS registros em produção (457 de 767): a maior
      # parte da carteira entra desativada e fora do painel. **É o que o legado
      # faz**, e a DEC-103b manda espelhar.
      limite_herdado(limite_auto_liquidaveis: 900_000, taxa_auto_liquidaveis: 3.1,
                     limite_fomento: 100_000, taxa_fomento: 1.0)

      described_class.expand_typed_controls!

      por_chave = RiskControl.where.not(risk_operation_type_id: nil)
                             .includes(:risk_operation_type)
                             .index_by { |c| c.risk_operation_type.integration_key }

      expect(por_chave['auto_liquidavel'].is_active).to be(false)
      expect(por_chave['fomento'].is_active).to be(true)
      expect(por_chave['comissaria'].is_active).to be(true)
      expect(por_chave['intercompany'].is_active).to be(true)
    end

    it 'resolves the type by integration_key, so renaming it on screen does not break the load' do
      # Escolha 3, contra a rotina de 2022: ela casava `when "Auto Liquidável"`.
      RiskOperationType.find_by(integration_key: 'fomento').update!(title: 'Fomento (novo nome)')
      limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)

      expect(described_class.expand_typed_controls!(io: nil)[:created]).to eq(4)
    end

    it 'PRESERVES the inherited row and its daily positions — never destroy_all (DEC-57)' do
      # A rotina de 2022 fazia `rc.risk_entries.destroy_all` seguido de
      # `rc.destroy`. Em produção isso apagaria 642.447 linhas de histórico.
      herdado = limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)
      posicao = create(:risk_entry, risk_control: herdado, company: company, project: project)

      described_class.expand_typed_controls!

      expect(RiskControl.exists?(herdado.id)).to be(true)
      expect(RiskEntry.exists?(posicao.id)).to be(true)
      expect(posicao.reload.risk_control_id).to eq(herdado.id)
    end

    it 'is idempotent — running twice creates nothing new' do
      limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5,
                     limite_comissaria: 300_000, taxa_comissaria: 1.8)


      described_class.expand_typed_controls!
      antes = RiskControl.count

      expect(described_class.expand_typed_controls![:created]).to eq(0)
      expect(RiskControl.count).to eq(antes)
    end

    it 'does not undo what the user changed on screen after the first load' do
      limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)
      described_class.expand_typed_controls!

      tipado = RiskControl.where.not(risk_operation_type_id: nil).first
      tipado.update!(limite: 999_999)

      described_class.expand_typed_controls!

      expect(tipado.reload.limite).to eq(999_999)
    end

    it 'skips with a message when the reference types were never seeded' do
      RiskControl.delete_all
      RiskOperationSubtype.delete_all
      RiskOperationType.delete_all

      resultado = described_class.expand_typed_controls!
      expect(resultado[:skipped_no_type]).to match_array(%w[auto_liquidavel comissaria fomento intercompany])
      expect(resultado[:created]).to eq(0)
    end
  end

  describe '.post_load! — the count DEC-43 asked for' do
    it 'reports both shapes' do
      limite_herdado(limite_fomento: 500_000, taxa_fomento: 2.5)
      described_class.expand_typed_controls!

      relatorio = described_class.post_load!
      expect(relatorio[:legacy_shape]).to eq(1)
      expect(relatorio[:typed]).to eq(4)
      expect(relatorio[:note]).to match(/NENHUMA linha da origem tem tipo/)
    end
  end
end
