# frozen_string_literal: true

require 'rails_helper'

# S5 / OPS-230, OPS-231 — os dois catálogos de referência do bloco de risco.
#
# O que este arquivo prova, e por que cada coisa importa:
#
# - **rodar duas vezes não duplica** — é o que torna o seed seguro no passo de
#   deploy;
# - **as 12 chaves de integração existem** — são contrato com o ETL (S14) e com
#   a resolução funcional dos movimentos (B-09);
# - **cada tipo dispara o `after_create` de subtipos exatamente uma vez** — se o
#   seed duplicasse o tipo, duplicaria os subtipos junto e o índice único de
#   (`tipo`, `is_pre`) estouraria.
RSpec.describe 'Seeds de referência do bloco de risco' do
  describe Seeds::Reference::RiskOperationTypes do
    it 'creates the four types with the exact legacy flags' do
      described_class.call!

      esperado = {
        'fomento' => { title: 'Fomento', manual: true, receivable: false, pre: false },
        'comissaria' => { title: 'Comissária', manual: false, receivable: true, pre: true },
        'intercompany' => { title: 'Intercompany', manual: false, receivable: true, pre: false },
        'auto_liquidavel' => { title: 'Auto Liquidável', manual: false, receivable: true, pre: true }
      }

      esperado.each do |chave, dados|
        tipo = RiskOperationType.find_by(integration_key: chave)
        expect(tipo).to be_present, "faltou o tipo «#{chave}»"
        expect(tipo.title).to eq(dados[:title])
        expect(tipo.allow_manual_operations).to be(dados[:manual])
        expect(tipo.allow_receivable_entries).to be(dados[:receivable])
        expect(tipo.has_pre_faturamento).to be(dados[:pre])
        expect(tipo.is_default).to be(true)
      end
    end

    it 'generates 1 or 2 subtypes per type — exactly once' do
      described_class.call!

      expect(RiskOperationType.find_by(integration_key: 'fomento').subtypes.count).to eq(1)
      expect(RiskOperationType.find_by(integration_key: 'comissaria').subtypes.count).to eq(2)
      expect(RiskOperationSubtype.count).to eq(1 + 2 + 1 + 2)
    end

    it 'is idempotent — a second run changes nothing' do
      described_class.call!
      antes = [RiskOperationType.count, RiskOperationSubtype.count]

      relatorio = described_class.call!

      expect([RiskOperationType.count, RiskOperationSubtype.count]).to eq(antes)
      expect(relatorio).to be_idempotent
    end

    it 'does NOT undo what the user changed on screen' do
      described_class.call!
      fomento = RiskOperationType.find_by(integration_key: 'fomento')
      fomento.update!(title: 'Fomento (nosso nome)')

      described_class.call!

      expect(fomento.reload.title).to eq('Fomento (nosso nome)')
      # E a chave continua sendo a de contrato.
      expect(fomento.integration_key).to eq('fomento')
    end
  end

  describe Seeds::Reference::RiskMovementTypes do
    it 'creates the eight types with the right credit sign' do
      described_class.call!

      esperado = {
        'juros' => 'D', 'advalorem' => 'D', 'iof' => 'D',
        'liberacao_do_recurso' => 'D', 'liquidacao' => 'C', 'juros_de_mora' => 'D',
        'transferencia_recebida' => 'D', 'valor_transferido' => 'C'
      }

      esperado.each do |chave, sinal|
        tipo = RiskMovementType.find_by(integration_key: chave)
        expect(tipo).to be_present, "faltou o tipo «#{chave}»"
        expect(tipo.credit_type_code).to eq(sinal)
        expect(tipo.is_default).to be(true)
      end
    end

    it 'marks the release as system exclusive and the two transfers as transfers' do
      described_class.call!

      expect(RiskMovementType.release.is_system_exclusive).to be(true)
      expect(RiskMovementType.transfer_out.is_transfer).to be(true)
      expect(RiskMovementType.transfer_in.is_transfer).to be(true)
    end

    it 'makes the three functional lookups work right after the seed (B-09)' do
      described_class.call!

      expect { RiskMovementType.release }.not_to raise_error
      expect { RiskMovementType.transfer_out }.not_to raise_error
      expect { RiskMovementType.transfer_in }.not_to raise_error
    end

    it 'is idempotent' do
      described_class.call!
      antes = RiskMovementType.count

      relatorio = described_class.call!

      expect(RiskMovementType.count).to eq(antes)
      expect(relatorio).to be_idempotent
    end
  end

  describe 'the two are wired into the single loader (OPS-540)' do
    it 'appears in Runner::CATALOGS with the model it requires' do
      chaves = Seeds::Reference::Runner::CATALOGS.map { |c| c[:seeder] }
      expect(chaves).to include('Seeds::Reference::RiskOperationTypes',
                                'Seeds::Reference::RiskMovementTypes')
    end

    it 'runs through the loader and reports' do
      relatorios = Seeds::Reference::Runner.call!
      nomes = relatorios.map(&:catalog)
      expect(nomes).to include('Tipos de limite de risco (OPS-230)',
                               'Movimentações de risco (OPS-231)')
    end
  end
end
