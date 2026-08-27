# frozen_string_literal: true

require 'rails_helper'

# O registro ficou VAZIO entre o trim (Blocos 6 e 7) e a chegada do assistente:
# `lead_capture` saiu com o AI9-006 e `assets` com o AI9-014. O que este spec
# protegia então era só o contrato da máquina de formatação por provider — o
# núcleo multi-provider do AI9-007 que o DEC-13.2 manda manter.
#
# Agora ele protege as duas coisas: aquela máquina **e** o contrato das
# capabilities do assistente, incluindo a regra que não se lê no código de um
# handler isolado — **nenhuma ferramenta grava, e nenhuma alcança administração**.
RSpec.describe Ai::Tools::ToolRegistry do
  def todas_as_specs
    described_class::CAPABILITY_TOOLS.values.flatten
  end

  describe 'CAPABILITY_TOOLS' do
    it 'registra as duas capabilities do assistente do console' do
      expect(described_class::CAPABILITY_TOOLS.keys).to contain_exactly('console_help', 'console_data')
    end

    it 'separa o acervo de ajuda do dado operacional' do
      expect(described_class::CAPABILITY_TOOLS['console_help'].map { |s| s[:name] })
        .to contain_exactly('search_faq', 'read_faq_item', 'field_help')
      expect(described_class::CAPABILITY_TOOLS['console_data'].map { |s| s[:name] })
        .to contain_exactly('project_snapshot', 'overdue_renegotiations', 'volume_by_carrier')
    end

    it 'toda spec tem nome, descrição e schema de objeto' do
      todas_as_specs.each do |spec|
        expect(spec[:name]).to be_present
        expect(spec[:description]).to be_present
        expect(spec[:parameters][:type]).to eq('object')
        expect(spec[:parameters][:properties]).to be_a(Hash)
      end
    end

    # O nome da ferramenta é o que o modelo vê e é por ele que ele decide o que
    # chamar. Um verbo de escrita aqui seria a primeira ferramenta capaz de
    # gravar por conversa — e a trilha registraria como ato do usuário algo que
    # ele nunca preencheu num formulário.
    it 'nenhuma ferramenta tem nome de escrita' do
      proibidos = /\A(create|update|delete|destroy|save|set|write|approve|cancel|pay|send)_/

      todas_as_specs.each do |spec|
        expect(spec[:name]).not_to match(proibidos)
      end
    end

    it 'o enum da ajuda de campo vem do próprio FieldHelp, não de uma cópia' do
      spec = described_class::CAPABILITY_TOOLS['console_help'].find { |s| s[:name] == 'field_help' }

      expect(spec[:parameters][:properties][:scope][:enum]).to eq(Help::FieldHelp::SCOPES)
    end
  end

  describe '.definitions_for' do
    it 'formata para o Anthropic com input_schema' do
      defs = described_class.definitions_for('anthropic', ['console_help'])

      expect(defs.size).to eq(3)
      expect(defs.first).to include(:name, :description, :input_schema)
    end

    it 'formata para a OpenAI com type function' do
      defs = described_class.definitions_for('openai', ['console_data'])

      expect(defs.size).to eq(3)
      expect(defs.first[:type]).to eq('function')
      expect(defs.first[:function]).to include(:name, :description, :parameters)
    end

    it 'formata para o Google como um bloco de functionDeclarations' do
      defs = described_class.definitions_for('google', %w[console_help console_data])

      expect(defs.size).to eq(1)
      expect(defs.first[:functionDeclarations].size).to eq(6)
    end

    it 'soma as capabilities pedidas, sem repetir' do
      expect(described_class.definitions_for('anthropic', %w[console_help console_help]).size).to eq(3)
    end

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
      end
    end

    context 'unknown provider' do
      it 'returns empty array' do
        expect(described_class.definitions_for('unknown', ['console_help'])).to eq([])
      end
    end
  end
end
