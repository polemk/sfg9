# frozen_string_literal: true

require 'rails_helper'

# S10 / 10.2 — **caracterização `G3`** do `design.md` §2, e o contrato **C2**.
#
# O exemplo que dá nome a este arquivo é o de baixo: a grade otimizada devolve
# **exatamente as mesmas linhas** que a montagem ingênua célula a célula do
# legado. Otimização que muda resultado é defeito, não melhoria (Princípio 9), e
# um teste de contagem de consultas sozinho não provaria isso.
RSpec.describe Indicators::EntryService do
  let(:projeto) { create(:project) }
  let(:outro_projeto) { create(:project) }
  let(:usuario) { create(:user) }

  let!(:margem) { create(:indicator, title: 'MARGEM') }
  let!(:atraso) { create(:indicator, title: 'ATRASO') }

  before do
    create(:project_indicator_connection, project: projeto, indicator: margem)
    create(:project_indicator_connection, project: projeto, indicator: atraso)
  end

  # ---------------------------------------------------------------------------
  describe '#grid — G3' do
    before do
      create(:indicator_entry, project: projeto, indicator: margem, year: 2024, month: 3, value: 0)
      create(:indicator_entry, project: projeto, indicator: margem, year: 2024, month: 4, value: 1_000)
      create(:indicator_entry, project: projeto, indicator: atraso, year: 2024, month: 7, value: -50)
    end

    # **O exemplo que trava a otimização.** Reproduz a montagem do legado —
    # `project.indicator_entry_on_month_and_indicator(m, year, i)` dentro de dois
    # laços (`_widget.html.erb:13-14`), 12 consultas por indicador — e compara
    # linha a linha com a consulta única.
    it 'devolve as MESMAS linhas que a montagem ingênua, célula a célula' do
      otimizada = described_class.grid(project: projeto, year: 2024)

      ingenua = described_class.grid_indicators(project: projeto).map do |indicador|
        {
          indicator: indicador,
          cells: (1..12).map do |m|
            { month: m,
              entry: described_class.entry_on_month_and_indicator(project: projeto, indicator: indicador,
                                                                  month: m, year: 2024) }
          end
        }
      end

      expect(otimizada.map { |l| l[:indicator].id }).to eq(ingenua.map { |l| l[:indicator].id })
      otimizada.zip(ingenua).each do |a, b|
        expect(a[:cells].map { |c| [c[:month], c[:entry]&.id] })
          .to eq(b[:cells].map { |c| [c[:month], c[:entry]&.id] })
      end
    end

    it 'monta 2 indicadores × 12 meses em UMA consulta de lançamentos' do
      consultas = []
      assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        consultas << payload[:sql] if payload[:sql].include?('FROM "indicator_entries"')
      end

      described_class.grid(project: projeto, year: 2024)
      ActiveSupport::Notifications.unsubscribe(assinatura)

      # No legado seriam 24 por indicador (o método é chamado duas vezes por
      # célula, no `.blank?` e no valor): 48 consultas para esta mesma tela.
      expect(consultas.size).to eq(1)
    end

    # **DEC-70.** É a leitura mais usada do módulo.
    it 'distingue NÃO LANÇADO (`nil`) de LANÇADO COMO ZERO (`0`)' do
      linha = described_class.grid(project: projeto, year: 2024).find { |l| l[:indicator].id == margem.id }

      marco = linha[:cells].find { |c| c[:month] == 3 }
      abril = linha[:cells].find { |c| c[:month] == 4 }
      maio  = linha[:cells].find { |c| c[:month] == 5 }

      expect(marco[:entry]).to be_present
      expect(marco[:entry].value).to eq(0)
      expect(abril[:entry].value).to eq(1_000)
      # Maio nunca foi lançado. No legado a view instanciava um
      # `IndicatorEntry.new` aqui e renderizava `0`.
      expect(maio[:entry]).to be_nil
    end

    it 'aplica a ordenação alfabética — no legado o `.order(title: :asc)` não era reatribuído' do
      expect(described_class.grid(project: projeto, year: 2024).map { |l| l[:indicator].title })
        .to eq(%w[ATRASO MARGEM])
    end

    it 'não mostra indicador INATIVO — replicado (`where(is_active: 1)`)' do
      atraso.update!(is_active: false)

      expect(described_class.grid(project: projeto, year: 2024).map { |l| l[:indicator].id }).to eq([margem.id])
    end

    it 'não mostra indicador DESCARTADO' do
      atraso.discard!

      expect(described_class.grid(project: projeto, year: 2024).map { |l| l[:indicator].id }).to eq([margem.id])
    end

    it 'não mostra indicador que não está CONECTADO ao projeto' do
      solto = create(:indicator, title: 'SOLTO')

      expect(described_class.grid(project: projeto, year: 2024).map { |l| l[:indicator].id })
        .not_to include(solto.id)
    end

    it 'com `month` devolve UMA célula por indicador — é o modo mês único' do
      linhas = described_class.grid(project: projeto, year: 2024, month: 4)

      expect(linhas.map { |l| l[:cells].size }).to all(eq(1))
      expect(linhas.find { |l| l[:indicator].id == margem.id }[:cells].first[:entry].value).to eq(1_000)
    end

    it 'com `indicator_id` devolve só aquele indicador' do
      linhas = described_class.grid(project: projeto, year: 2024, indicator_id: margem.id)

      expect(linhas.map { |l| l[:indicator].id }).to eq([margem.id])
    end

    it 'NUNCA vaza lançamento de outro projeto (C1)' do
      create(:project_indicator_connection, project: outro_projeto, indicator: margem)
      create(:indicator_entry, project: outro_projeto, indicator: margem, year: 2024, month: 5, value: 999)

      linha = described_class.grid(project: projeto, year: 2024).find { |l| l[:indicator].id == margem.id }
      expect(linha[:cells].find { |c| c[:month] == 5 }[:entry]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  describe '#upsert — BE-326' do
    it 'cria a célula com 201 e o autor vindo do SERVIDOR' do
      resultado = described_class.upsert(project: projeto, indicator_id: margem.id, year: 2024, month: 6,
                                         value: 42, actor: usuario)

      expect(resultado[:status]).to eq(201)
      expect(resultado[:data].created_by).to eq(usuario.id)
      expect(resultado[:data].project_id).to eq(projeto.id)
    end

    # O defeito: no legado a segunda gravação da mesma célula falhava com
    # "já está em uso" (era `create`, não upsert) — e como não havia handler de
    # erro no `$.ajax`, o usuário via o campo destravar e **acreditava que salvou**.
    it 'a SEGUNDA gravação da mesma célula ATUALIZA, não falha' do
      described_class.upsert(project: projeto, indicator_id: margem.id, year: 2024, month: 6,
                             value: 42, actor: usuario)
      segunda = described_class.upsert(project: projeto, indicator_id: margem.id, year: 2024, month: 6,
                                       value: 99, actor: usuario)

      expect(segunda[:status]).to eq(200)
      expect(segunda[:data].value).to eq(99)
      expect(IndicatorEntry.where(project: projeto, indicator: margem, year: 2024, month: 6).count).to eq(1)
    end

    it 'mantém `created_by` e troca `updated_by` na atualização' do
      outro = create(:user)
      described_class.upsert(project: projeto, indicator_id: margem.id, year: 2024, month: 6,
                             value: 1, actor: usuario)
      resultado = described_class.upsert(project: projeto, indicator_id: margem.id, year: 2024, month: 6,
                                         value: 2, actor: outro)

      expect(resultado[:data].created_by).to eq(usuario.id)
      expect(resultado[:data].updated_by).to eq(outro.id)
    end

    it 'zero é gravado como lançamento de verdade' do
      resultado = described_class.upsert(project: projeto, indicator_id: margem.id, year: 2024, month: 8,
                                         value: 0, actor: usuario)

      expect(resultado[:status]).to eq(201)
      expect(resultado[:data].value).to eq(0)
    end

    it 'indicador de OUTRO projeto devolve 404, não grava' do
      especifico = create(:indicator, :specific, title: 'SO DO OUTRO', project: outro_projeto)

      resultado = described_class.upsert(project: projeto, indicator_id: especifico.id, year: 2024, month: 1,
                                         value: 1, actor: usuario)
      expect(resultado[:status]).to eq(404)
    end

    it 'mês fora da faixa é 422' do
      resultado = described_class.upsert(project: projeto, indicator_id: margem.id, year: 2024, month: 13,
                                         value: 1, actor: usuario)

      expect(resultado[:status]).to eq(422)
    end
  end

  # ---------------------------------------------------------------------------
  describe '#update — BE-327' do
    let!(:entrada) do
      create(:indicator_entry, project: projeto, indicator: margem, year: 2024, month: 2, value: 5)
    end

    it 'atualiza o valor e marca quem alterou' do
      resultado = described_class.update(project: projeto, id: entrada.id, attrs: { value: 77 }, actor: usuario)

      expect(resultado[:status]).to eq(200)
      expect(resultado[:data].value).to eq(77)
      expect(resultado[:data].updated_by).to eq(usuario.id)
    end

    it 'lançamento de OUTRO projeto é 404 — nunca 403 (não é oráculo de id)' do
      alheio = create(:indicator_entry, project: outro_projeto, indicator: margem, year: 2024, month: 2)

      expect(described_class.update(project: projeto, id: alheio.id, attrs: { value: 1 })[:status]).to eq(404)
    end

    it 'indicador inexistente é 422, não 500' do
      resultado = described_class.update(project: projeto, id: entrada.id,
                                         attrs: { indicator_id: SecureRandom.uuid })

      expect(resultado[:status]).to eq(422)
    end
  end

  # ---------------------------------------------------------------------------
  describe '#destroy — BE-328 / DEC-71 (endpoint sem tela)' do
    it 'apaga e a célula volta ao estado NÃO LANÇADO — o efeito que a DEC-70 tornou visível' do
      entrada = create(:indicator_entry, project: projeto, indicator: margem, year: 2024, month: 9, value: 3)

      expect(described_class.destroy(project: projeto, id: entrada.id, actor: usuario)[:status]).to eq(200)

      linha = described_class.grid(project: projeto, year: 2024).find { |l| l[:indicator].id == margem.id }
      expect(linha[:cells].find { |c| c[:month] == 9 }[:entry]).to be_nil
    end

    it 'lançamento de outro projeto é 404' do
      alheio = create(:indicator_entry, project: outro_projeto, indicator: margem, year: 2024, month: 9)

      expect(described_class.destroy(project: projeto, id: alheio.id)[:status]).to eq(404)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'as 4 consultas do legado (BE-716) — e SÓ elas' do
    before do
      create(:indicator_entry, project: projeto, indicator: margem, year: 2024, month: 3, value: 10)
      create(:indicator_entry, project: projeto, indicator: atraso, year: 2024, month: 3, value: 20)
    end

    it 'entry_on_month_and_indicator' do
      entrada = described_class.entry_on_month_and_indicator(project: projeto, indicator: margem,
                                                             month: 3, year: 2024)
      expect(entrada.value).to eq(10)
    end

    it 'entries_on_month — portada sem endpoint (não tem chamador no legado)' do
      expect(described_class.entries_on_month(project: projeto, month: 3, year: 2024).count).to eq(2)
    end

    it 'entries_on_indicator — idem' do
      expect(described_class.entries_on_indicator(project: projeto, indicator: margem).count).to eq(1)
    end

    # A única das quatro em que o resultado muda, e é a DEC-70: o legado
    # devolvia `IndicatorEntry.new(value: 0)` para o indicador sem lançamento —
    # inventava um zero.
    it 'all_entries_on_month devolve `nil` no lugar do zero inventado (DEC-70)' do
      linhas = described_class.all_entries_on_month(project: projeto, month: 5, year: 2024)

      expect(linhas.size).to eq(2)
      expect(linhas.map { |l| l[:entry] }).to all(be_nil)
    end

    it 'NÃO existe cálculo de variação, acumulado, média nem gráfico (DEC-09)' do
      metodos = described_class.methods(false).map(&:to_s)
      expect(metodos.grep(/variation|variacao|accumulated|acumulado|average|media|chart|grafico/)).to be_empty
    end
  end
end
