# frozen_string_literal: true

require 'rails_helper'

# S10 / 10.4 — o catálogo (`BE-316`, `BE-317`, `BE-318`, `BE-319`) e a
# caracterização **`G4`** vista pelo serviço.
RSpec.describe Indicators::IndicatorService do
  let(:projeto) { create(:project) }
  let(:outro_projeto) { create(:project) }
  let(:usuario) { create(:user) }

  describe '#index — só os GLOBAIS (BE-311)' do
    it 'não lista específicos de projeto nenhum' do
      global = create(:indicator, title: 'GLOBAL')
      create(:indicator, :specific, title: 'ESPECIFICO', project: projeto)

      expect(described_class.index(params: {})[:data].map(&:id)).to eq([global.id])
    end

    it 'não lista descartados' do
      create(:indicator, :discarded, title: 'FORA')
      vivo = create(:indicator, title: 'DENTRO')

      expect(described_class.index(params: {})[:data].map(&:id)).to eq([vivo.id])
    end

    it 'devolve a RELAÇÃO, não um array — quem materializa antes do limite carrega tudo (D-20)' do
      expect(described_class.index(params: {})[:data]).to be_a(ActiveRecord::Relation)
    end

    it 'a busca é por título OU chave, com o termo escapado' do
      create(:indicator, title: 'MARGEM BRUTA')
      create(:indicator, title: 'ATRASO')

      expect(described_class.index(params: { q: 'margem' })[:data].map(&:title)).to eq(['MARGEM BRUTA'])
      # `%` do usuário é texto literal, não curinga (o legado montava o padrão
      # dentro da string, via `Dev.ilike`).
      expect(described_class.index(params: { q: '%' })[:data]).to be_empty
    end
  end

  describe '#create — BE-316' do
    it 'cria global sem conexão nenhuma' do
      resultado = described_class.create(attrs: { title: 'Margem' }, actor: usuario)

      expect(resultado[:status]).to eq(201)
      expect(resultado[:data]).to be_global
      expect(ProjectIndicatorConnection.count).to eq(0)
    end

    it 'com projeto cria o específico E a conexão, na MESMA transação' do
      resultado = described_class.create(attrs: { title: 'Margem do projeto' }, project: projeto, actor: usuario)

      expect(resultado[:status]).to eq(201)
      expect(resultado[:data].project_id).to eq(projeto.id)
      expect(ProjectIndicatorConnection.where(project: projeto, indicator: resultado[:data]).count).to eq(1)
    end

    # No legado, quando o `Indicator.create` falhava, a linha seguinte ainda
    # chamava `ProjectIndicatorConnection.create(indicator_id: nil, …)` — que
    # falhava em silêncio por validação de presença. Nada era dito ao usuário.
    it 'indicador inválido NÃO deixa conexão órfã' do
      create(:indicator, title: 'MARGEM')
      resultado = described_class.create(attrs: { title: 'margem' }, project: projeto, actor: usuario)

      expect(resultado[:status]).to eq(422)
      expect(ProjectIndicatorConnection.count).to eq(0)
      expect(Indicator.count).to eq(1)
    end
  end

  describe '#update — BE-317' do
    it 'um save só: a propagação NÃO roda duas vezes' do
      indicador = create(:indicator, title: 'ANTES')
      create(:indicator_entry, project: projeto, indicator: indicador)

      expect(IndicatorEntry).to receive(:propagate_from).once.and_call_original
      described_class.update(id: indicador.id, attrs: { title: 'DEPOIS' }, actor: usuario)
    end

    # No legado trocar `project_id` **não** criava nem removia a conexão: o
    # indicador virava específico sem conexão e sumia da tela do projeto.
    it 'virar ESPECÍFICO cria a conexão' do
      indicador = create(:indicator, title: 'GLOBAL')

      described_class.update(id: indicador.id, attrs: {}, project: projeto, scope_change: :project)

      expect(indicador.reload.project_id).to eq(projeto.id)
      expect(ProjectIndicatorConnection.where(project: projeto, indicator: indicador).count).to eq(1)
    end

    it 'virar GLOBAL remove as conexões' do
      indicador = create(:indicator, :specific, title: 'ESPECIFICO', project: projeto)
      create(:project_indicator_connection, project: projeto, indicator: indicador)

      described_class.update(id: indicador.id, attrs: {}, scope_change: :global)

      expect(indicador.reload).to be_global
      expect(ProjectIndicatorConnection.where(indicator: indicador).count).to eq(0)
    end

    it 'a chave NÃO é gravável no update, mesmo se vier no corpo (DEC-85)' do
      indicador = create(:indicator, title: 'ORIGINAL')

      described_class.update(id: indicador.id, attrs: { key: 'chave_nova' })

      expect(indicador.reload.key).to eq('original')
    end

    it 'id inexistente é 404' do
      expect(described_class.update(id: SecureRandom.uuid, attrs: {})[:status]).to eq(404)
    end

    it 'id malformado é 404, não `PG::InvalidTextRepresentation` → 500' do
      expect(described_class.update(id: 'nao-e-uuid', attrs: {})[:status]).to eq(404)
    end
  end

  describe '#activate — BE-319' do
    it 'desativa' do
      indicador = create(:indicator, title: 'X')

      expect(described_class.activate(id: indicador.id, is_active: false)[:status]).to eq(200)
      expect(indicador.reload.is_active).to be(false)
    end

    it 'id inexistente é 404 — no legado era `nil.is_active=` → 500' do
      expect(described_class.activate(id: SecureRandom.uuid, is_active: true)[:status]).to eq(404)
    end
  end

  describe '#destroy — BE-318, o fechamento do D-66' do
    let(:indicador) { create(:indicator, title: 'COM HISTORICO') }
    let!(:lancamentos) do
      [1, 2, 3].map { |m| create(:indicator_entry, project: projeto, indicator: indicador, month: m, value: m * 10) }
    end

    it 'a exclusão PRESERVA os lançamentos e diz quantos' do
      resultado = described_class.destroy(id: indicador.id, actor: usuario)

      expect(resultado[:status]).to eq(200)
      expect(resultado[:data][:entries_preserved]).to eq(3)
      expect(IndicatorEntry.where(indicator_id: indicador.id).count).to eq(3)
      expect(lancamentos.map { |l| l.reload.value }).to eq([10, 20, 30])
    end

    it 'o indicador sai das listas' do
      described_class.destroy(id: indicador.id, actor: usuario)

      expect(described_class.index(params: {})[:data].map(&:id)).not_to include(indicador.id)
      expect(described_class.show(id: indicador.id)[:status]).to eq(404)
    end

    it 'o impacto é lido ANTES da escrita e traz projeto e contagem (FE-315)' do
      resultado = described_class.deletion_impact(id: indicador.id)

      expect(resultado[:data][:entries_count]).to eq(3)
      expect(resultado[:data][:projects].map { |p| p[:name] }).to include(projeto.name)
      # Nada foi escrito.
      expect(indicador.reload.discarded_at).to be_nil
    end
  end

  describe 'contagens em UMA consulta (não N+1)' do
    it 'entry_counts e connection_counts respondem para a página inteira' do
      a = create(:indicator, title: 'A')
      b = create(:indicator, title: 'B')
      create(:indicator_entry, project: projeto, indicator: a, month: 1)
      create(:indicator_entry, project: projeto, indicator: a, month: 2)
      create(:project_indicator_connection, project: outro_projeto, indicator: a)

      expect(described_class.entry_counts([a.id, b.id])).to eq(a.id => 2)
      # `a` está conectado aos dois projetos: o do lançamento e o outro.
      expect(described_class.connection_counts([a.id, b.id])).to eq(a.id => 2)
    end
  end
end
