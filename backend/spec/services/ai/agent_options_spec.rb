# frozen_string_literal: true

require 'rails_helper'

# O marcador [opcoes: ...] e sintaxe interna: precisa virar dado estruturado aqui,
# antes de o texto seguir para o widget do site ou para os canais sociais.
RSpec.describe Ai::AgentService, '.extract_options' do
  def extrair(texto)
    described_class.send(:extract_options, texto)
  end

  it 'separa o texto das opções' do
    limpo, opcoes = extrair("Esse ficou parecido.\n\n[opcoes: Ver por dentro | Quanto custa]")

    expect(limpo).to eq('Esse ficou parecido.')
    expect(opcoes).to eq([{ label: 'Ver por dentro', value: 'Ver por dentro' },
                          { label: 'Quanto custa', value: 'Quanto custa' }])
  end

  it 'aceita singular e acento como o modelo costuma escrever' do
    %w[opcoes opções opcao opção].each do |variante|
      limpo, opcoes = extrair("Confirma? [#{variante}: Sim | Não]")

      expect(limpo).to eq('Confirma?'), "falhou para '#{variante}'"
      expect(opcoes.map { |o| o[:label] }).to eq(%w[Sim Não])
    end
  end

  it 'não deixa marcador nenhum escapar quando o modelo repete o padrão' do
    limpo, opcoes = extrair('Um [opcoes: A | B] dois [opcoes: C | D] fim')

    expect(limpo).not_to include('[')
    expect(limpo).to eq('Um dois fim')
    expect(opcoes.map { |o| o[:label] }).to eq(%w[C D]), 'o último marcador é a escolha final'
  end

  it 'limita a três botões' do
    _limpo, opcoes = extrair('[opcoes: A | B | C | D | E]')

    expect(opcoes.size).to eq(3)
  end

  it 'corta rótulo longo sem deixar preposição pendurada' do
    _limpo, opcoes = extrair('[opcoes: Falar com um especialista | Ver o orçamento completo]')

    expect(opcoes.map { |o| o[:label] }).to eq(['Falar', 'Ver o orçamento'])
    expect(opcoes.first[:value]).to eq('Falar com um especialista'), 'o payload mantém o texto inteiro'
  end

  it 'preserva rótulo que já cabe' do
    _limpo, opcoes = extrair('[opcoes: Ver vídeo | Ver foto]')

    expect(opcoes.map { |o| o[:label] }).to eq(['Ver vídeo', 'Ver foto'])
  end

  it 'ignora marcador vazio e texto sem marcador' do
    expect(extrair('Texto puro')).to eq(['Texto puro', []])
    expect(extrair('Nada aqui [opcoes: ]')).to eq(['Nada aqui', []])
    expect(extrair(nil)).to eq([nil, []])
  end
end
