# frozen_string_literal: true

require 'rails_helper'

# S10 / 10.5 — conexões e indicadores específicos (`BE-707`, `BE-709`, `BE-710`,
# `BE-711`).
RSpec.describe Indicators::ConnectionService do
  let(:projeto) { create(:project) }
  let(:outro_projeto) { create(:project) }
  let(:usuario) { create(:user) }

  let!(:global) { create(:indicator, title: 'GLOBAL') }
  let!(:meu_especifico) { create(:indicator, :specific, title: 'MEU', project: projeto) }
  let!(:especifico_alheio) { create(:indicator, :specific, title: 'ALHEIO', project: outro_projeto) }

  describe '#connectable — BE-707' do
    it 'traz globais + específicos DESTE projeto, e nunca o específico alheio' do
      ids = described_class.connectable(project: projeto, params: {}).map(&:id)

      expect(ids).to contain_exactly(global.id, meu_especifico.id)
    end

    # Os ramos `if connection_type == "Carrier"/"Project"` do legado nunca casam
    # com "Indicator", então `q` era simplesmente ignorado — a busca da tela
    # não filtrava nada, e o front chamava com `l=200`.
    it 'a busca FILTRA de verdade' do
      expect(described_class.connectable(project: projeto, params: { q: 'meu' }).map(&:id)).to eq([meu_especifico.id])
    end

    it 'não traz descartado' do
      global.discard!

      expect(described_class.connectable(project: projeto, params: {}).map(&:id)).to eq([meu_especifico.id])
    end

    # O que substituiu o `params[:connection_type].constantize`: não existe tipo
    # dinâmico nenhum na superfície.
    it 'o serviço não aceita tipo dinâmico — a assinatura não tem `connection_type`' do
      expect(described_class.method(:connectable).parameters.map(&:last)).to contain_exactly(:project, :params)
    end
  end

  describe '#connect — BE-709' do
    it 'conecta vários de uma vez e devolve relatório por item' do
      resultado = described_class.connect(project: projeto, indicator_ids: [global.id, meu_especifico.id],
                                          actor: usuario)

      expect(resultado[:status]).to eq(200)
      expect(resultado[:data][:items].map { |i| i[:ok] }).to all(be(true))
      expect(described_class.connected_ids(projeto)).to include(global.id, meu_especifico.id)
    end

    # No legado o laço reatribuía `@connection` a cada volta e nem verificava o
    # `save`: conectar 3 com 1 falha podia reportar sucesso.
    it 'um item inválido REPROVA o lote inteiro e diz qual falhou' do
      resultado = described_class.connect(project: projeto,
                                          indicator_ids: [global.id, especifico_alheio.id], actor: usuario)

      expect(resultado[:status]).to eq(422)
      falhou = resultado[:details][:items].find { |i| !i[:ok] }
      expect(falhou[:indicator_id]).to eq(especifico_alheio.id)
      # E nada foi gravado: a transação voltou atrás.
      expect(described_class.connected_ids(projeto)).to be_empty
    end

    it 'conectar duas vezes é sucesso, não erro — o interruptor é estado, não comando' do
      described_class.connect(project: projeto, indicator_ids: [global.id])
      segunda = described_class.connect(project: projeto, indicator_ids: [global.id])

      expect(segunda[:status]).to eq(200)
      expect(ProjectIndicatorConnection.where(project: projeto, indicator: global).count).to eq(1)
    end

    it 'lista vazia é 422' do
      expect(described_class.connect(project: projeto, indicator_ids: [])[:status]).to eq(422)
    end
  end

  describe '#disconnect — BE-710 / Q-R31' do
    before { described_class.connect(project: projeto, indicator_ids: [global.id]) }

    let!(:lancamentos) do
      [1, 2].map { |m| create(:indicator_entry, project: projeto, indicator: global, month: m, value: m) }
    end

    it 'desconectar NÃO apaga lançamento — o histórico continua no banco' do
      described_class.disconnect(project: projeto, indicator_ids: [global.id])

      expect(IndicatorEntry.where(project: projeto, indicator: global).count).to eq(2)
    end

    it 'reconectar traz o histórico de volta inteiro (replicado, Q-R31)' do
      described_class.disconnect(project: projeto, indicator_ids: [global.id])
      described_class.connect(project: projeto, indicator_ids: [global.id])

      linhas = Indicators::EntryService.grid(project: projeto, year: lancamentos.first.year)
      linha = linhas.find { |l| l[:indicator].id == global.id }
      expect(linha[:cells].select { |c| c[:entry] }.size).to eq(2)
    end

    it 'par inexistente é no-op idempotente, não `nil.destroy` → 500' do
      described_class.disconnect(project: projeto, indicator_ids: [global.id])
      segunda = described_class.disconnect(project: projeto, indicator_ids: [global.id])

      expect(segunda[:status]).to eq(200)
    end
  end

  describe '#destroy_specific — BE-711' do
    before do
      described_class.connect(project: projeto, indicator_ids: [meu_especifico.id, global.id])
    end

    it 'exclui o específico: a conexão sai e o indicador vai para a exclusão LÓGICA' do
      create(:indicator_entry, project: projeto, indicator: meu_especifico, month: 1, value: 7)

      resultado = described_class.destroy_specific(project: projeto, indicator_id: meu_especifico.id,
                                                   actor: usuario)

      expect(resultado[:status]).to eq(200)
      expect(ProjectIndicatorConnection.where(indicator: meu_especifico).count).to eq(0)
      expect(meu_especifico.reload.discarded_at).to be_present
      # **O D-66:** no legado esta tela nem tinha diálogo de confirmação e o
      # `delete_all` levava a série junto.
      expect(IndicatorEntry.where(indicator: meu_especifico).count).to eq(1)
    end

    # No legado este ramo levantava `NoMethodError`: `@connection` vinha do
    # `before_action` e era uma `Relation`, não um record.
    it 'indicador GLOBAL é recusado com 422 e a frase, em vez de estourar' do
      resultado = described_class.destroy_specific(project: projeto, indicator_id: global.id)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to match(/globais com associação/)
      expect(global.reload.discarded_at).to be_nil
    end

    it 'específico de OUTRO projeto é 404 — não é oráculo de id' do
      expect(described_class.destroy_specific(project: projeto, indicator_id: especifico_alheio.id)[:status])
        .to eq(404)
    end

    it 'id malformado é 404, não 500' do
      expect(described_class.destroy_specific(project: projeto, indicator_id: 'xxx')[:status]).to eq(404)
    end
  end
end
