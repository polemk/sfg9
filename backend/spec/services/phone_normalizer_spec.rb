# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoneNormalizer do
  describe '.normalize' do
    context 'mesmo número em formatos diferentes' do
      let(:canonical) { '5548988051484' }

      it 'normaliza forma já canônica' do
        expect(described_class.normalize('5548988051484')).to eq(canonical)
      end

      it 'remove o prefixo +' do
        expect(described_class.normalize('+5548988051484')).to eq(canonical)
      end

      it 'remove o sufixo de JID do WhatsApp' do
        expect(described_class.normalize('5548988051484@s.whatsapp.net')).to eq(canonical)
      end

      it 'prefixa o DDI quando ausente (DDD + móvel)' do
        expect(described_class.normalize('48988051484')).to eq(canonical)
      end
    end

    it 'remove máscara (parênteses, espaço, traço)' do
      expect(described_class.normalize('(48) 99999-9999')).to eq('5548999999999')
    end

    it 'aceita telefone fixo (10 dígitos sem DDI → 12 com DDI)' do
      expect(described_class.normalize('4833334444')).to eq('554833334444')
    end

    it 'mantém fixo já com DDI (12 dígitos)' do
      expect(described_class.normalize('554833334444')).to eq('554833334444')
    end

    context 'entradas inválidas' do
      it 'retorna nil para nil' do
        expect(described_class.normalize(nil)).to be_nil
      end

      it 'retorna nil para string vazia' do
        expect(described_class.normalize('')).to be_nil
      end

      it 'retorna nil para texto sem dígitos' do
        expect(described_class.normalize('abc')).to be_nil
      end

      it 'retorna nil para número curto demais' do
        expect(described_class.normalize('1234')).to be_nil
      end
    end

    it 'é idempotente (normalizar duas vezes não muda)' do
      once = described_class.normalize('(48) 98805-1484')
      expect(described_class.normalize(once)).to eq(once)
    end
  end
end
