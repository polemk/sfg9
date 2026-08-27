# frozen_string_literal: true

require 'rails_helper'

# ESTADO APÓS O TRIM (Phase 1b): o registro está VAZIO — `lead_capture` saiu no
# Bloco 6 com o AI9-006 e `assets` saiu no Bloco 7 com o AI9-014. O que este spec
# protege agora é o CONTRATO da máquina de formatação por provider, que é o núcleo
# multi-provider do AI9-007 e o ponto de extensão do assistente interno.
RSpec.describe Ai::Tools::ToolRegistry do
  describe 'CAPABILITY_TOOLS' do
    it 'está vazio — nenhuma capability sobreviveu ao trim' do
      expect(described_class::CAPABILITY_TOOLS).to eq({})
    end
  end

  describe '.definitions_for' do
    context 'sem capability' do
      it 'returns empty array' do
        expect(described_class.definitions_for('anthropic')).to eq([])
        expect(described_class.definitions_for('anthropic', [])).to eq([])
      end
    end

    context 'com capability que não existe mais' do
      it 'ignora em silêncio em vez de estourar' do
        expect(described_class.definitions_for('anthropic', %w[lead_capture assets])).to eq([])
        expect(described_class.definitions_for('openai', %w[assets])).to eq([])
        expect(described_class.definitions_for('google', %w[lead_capture])).to eq([])
      end
    end

    context 'unknown provider' do
      it 'returns empty array' do
        expect(described_class.definitions_for('unknown', ['assets'])).to eq([])
      end
    end
  end
end
