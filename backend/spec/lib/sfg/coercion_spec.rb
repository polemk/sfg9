# frozen_string_literal: true

require 'rails_helper'

# Teste golden do contrato C2 — OPS-619.
#
# Os casos NÃO são escritos aqui: vêm de `golden/coercion.json`, extraído executando
# o `config/initializers/type_casting.rb` do legado. O mesmo arquivo alimenta o
# cross-check do utilitário TS do front (`scripts/check-coercion-golden.mjs`), para
# que os dois lados leiam o mesmo conjunto — formatação divergente entre a tela e a
# gravação é o D-09 por outra porta.
RSpec.describe Sfg::Coercion do
  # Variavel local, nao constante: constante dentro de bloco vaza para Object.
  golden = JSON.parse(Rails.root.join('..', 'golden', 'coercion.json').read).freeze

  describe '.to_bool' do
    golden['string_to_bool'].each do |input, expected|
      it "converte #{input.inspect} em #{expected}" do
        expect(described_class.to_bool(input)).to eq(expected)
      end
    end

    golden['string_to_bool_raises'].each do |input|
      it "levanta ArgumentError em #{input.inspect} (o legado também levanta)" do
        expect { described_class.to_bool(input) }.to raise_error(ArgumentError)
      end
    end

    golden['integer_to_bool'].each do |input, expected|
      it "converte o inteiro #{input} em #{expected}" do
        expect(described_class.to_bool(input.to_i)).to eq(expected)
      end
    end

    golden['integer_to_bool_raises'].each do |input|
      it "levanta ArgumentError no inteiro #{input}" do
        expect { described_class.to_bool(input) }.to raise_error(ArgumentError)
      end
    end

    it 'trata nil como false' do
      expect(described_class.to_bool(nil)).to eq(golden['nil_to_bool'])
    end
  end

  describe '.bool_to_i' do
    it 'reproduz TrueClass#to_i e FalseClass#to_i do legado' do
      expect(described_class.bool_to_i(true)).to eq(golden['true_to_i'])
      expect(described_class.bool_to_i(false)).to eq(golden['false_to_i'])
    end
  end

  describe '.to_number' do
    golden['string_to_number'].each do |c|
      it "converte #{c['input'].inspect} em #{c['legacy'].inspect}#{c['note'] ? " (#{c['note']})" : ''}" do
        expect(described_class.to_number(c['input'])).to eq(c['legacy'])
      end
    end
  end

  describe '.to_currency' do
    golden['to_currency'].each do |c|
      it "formata #{c['input'].inspect} como #{c['legacy'].inspect}#{c['note'] ? " (#{c['note']})" : ''}" do
        expect(described_class.to_currency(c['input'])).to eq(c['legacy'])
      end
    end
  end

  describe '.with_precision' do
    golden['with_precision_2'].each do |c|
      it "arredonda #{c['input'].inspect} para #{c['legacy'].inspect}" do
        expect(described_class.with_precision(c['input'], 2)).to eq(c['legacy'])
      end
    end
  end

  # O ponto do OPS-619: a coerção deixou de ser monkey patch.
  describe 'ausência de monkey patch' do
    it 'não acrescenta #to_bool a String, Integer nem NilClass' do
      expect('true').not_to respond_to(:to_bool)
      expect(1).not_to respond_to(:to_bool)
      expect(nil).not_to respond_to(:to_bool)
    end

    it 'não acrescenta #to_currency a Float nem BigDecimal' do
      expect(1.0).not_to respond_to(:to_currency)
      expect(BigDecimal('1')).not_to respond_to(:to_currency)
    end
  end
end
