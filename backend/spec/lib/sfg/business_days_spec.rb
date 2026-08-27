# frozen_string_literal: true

require 'rails_helper'

# S11 / BE-127, DC-29 — **golden test dos dias úteis**.
#
# Os números abaixo foram conferidos contra `../sfg/app/decorators/models/date_decorator.rb`,
# que rejeita `cwday == 6` (sábado) e `cwday == 7` (domingo) e **nada mais**.
#
# **Este teste não existe para provar que a regra está certa.** Ele existe para
# reprovar quem "consertar" a regra sem passar por uma DEC nova (DEC-30). A
# DEC-28 manteve o defeito **D-03** conscientemente: em todo mês com feriado o
# multiplicador de correção fica alto, como sempre esteve. Isso **não é
# regressão**.
RSpec.describe Sfg::BusinessDays do
  describe 'dias úteis do mês' do
    # Agosto/2026: 1º é sábado, 31 é segunda. 21 dias úteis.
    it 'conta seg–sex do mês inteiro' do
      expect(described_class.in_month(Date.new(2026, 8, 14))).to eq(21)
    end

    # Fevereiro/2026: 28 dias, 1º é domingo. 20 dias úteis.
    it 'conta corretamente um mês curto' do
      expect(described_class.in_month(Date.new(2026, 2, 10))).to eq(20)
    end
  end

  describe 'dias úteis até a data' do
    it 'conta do primeiro dia do mês até a data, inclusive' do
      # 3, 4, 5, 6, 7, 10, 11, 12, 13, 14 de agosto/2026 = 10 dias úteis.
      expect(described_class.until_date(Date.new(2026, 8, 14))).to eq(10)
    end

    it 'conta 1 quando a data é o primeiro dia útil do mês' do
      expect(described_class.until_date(Date.new(2026, 8, 3))).to eq(1)
    end

    it 'conta 0 quando o mês começa no fim de semana e a data é o dia 1' do
      # 01/08/2026 é sábado: nenhum dia útil decorrido.
      expect(described_class.until_date(Date.new(2026, 8, 1))).to eq(0)
    end
  end

  describe 'multiplicador da correção' do
    it 'é a proporção do mês decorrida em dias úteis' do
      expect(described_class.multiplier(Date.new(2026, 8, 14))).to be_within(1e-9).of(10.0 / 21)
    end

    it 'é 1.0 no último dia útil do mês' do
      expect(described_class.multiplier(Date.new(2026, 8, 31))).to eq(1.0)
    end

    # **D-03, preservado por DEC-28.** Setembro/2026 tem o feriado de 7/9 (uma
    # segunda-feira). O legado o conta como dia útil, e o ai9 também: no dia 7 o
    # multiplicador já é 5/22, não 4/22.
    it 'CONTA o feriado como dia útil — DEC-28 manteve o D-03 de propósito' do
      sete_de_setembro = Date.new(2026, 9, 7)
      expect(sete_de_setembro.cwday).to eq(1) # é uma segunda-feira
      expect(described_class.until_date(sete_de_setembro)).to eq(5)
      expect(described_class.multiplier(sete_de_setembro)).to be_within(1e-9).of(5.0 / 22)
    end

    it 'devolve Float, não BigDecimal — trocar mudaria os centavos de todo o histórico' do
      expect(described_class.multiplier(Date.new(2026, 8, 14))).to be_a(Float)
    end
  end
end
