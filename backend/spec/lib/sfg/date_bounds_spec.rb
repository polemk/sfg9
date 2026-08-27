# frozen_string_literal: true

require 'rails_helper'

# **BE-538 — as sentinelas de `date_overload.rb`, do lado Ruby.**
#
# O legado reabria `DateTime` para acrescentar `dinosaurs`, `mars`,
# `today_start` e `today_end`. Elas decidem o que entra num filtro de período
# quando nenhuma ponta é informada — ou seja, decidem quais linhas aparecem num
# relatório de fechamento. Estavam portadas e **sem um único exemplo**.
#
# O preço de não ter exemplo aqui já foi cobrado: a porta TypeScript da mesma
# sentinela tinha divergido para o fim real do dia e ninguém percebeu, porque
# nem consumidor nem teste olhavam para nenhuma das duas.
RSpec.describe Sfg::DateBounds do
  # Local, e nao no `rails_helper`: a suite inteira nao usa viagem no tempo, e
  # nao e a vespera da demo que se mexe em infra compartilhada de teste.
  include ActiveSupport::Testing::TimeHelpers

  # Meia-noite tem de ser um RESULTADO, não uma coincidência da hora em que a
  # suíte roda. E sentinela que se calcula "agora" quebra sozinha à meia-noite:
  # um teste que passa de tarde e falha de madrugada é pior do que nenhum.
  around do |exemplo|
    travel_to(Time.zone.local(2026, 8, 27, 15, 42, 30)) { exemplo.run }
  end

  it 'today_start é a meia-noite de hoje' do
    expect(described_class.today_start).to eq(Time.zone.local(2026, 8, 27, 0, 0, 0))
  end

  # **Este exemplo trava uma falha do legado, de propósito.**
  #
  # `midnight + 23h59min` deixa de fora tudo entre 23:59:00 e 23:59:59 — um
  # registro gravado às 23:59:30 some do filtro "até hoje". É errado, e é
  # replicado: corrigir muda quais linhas entram num fechamento. Decisão
  # assinada em PLAT-07 do `improvements-log.md`.
  it 'today_end é 23:59:00 — e NÃO 23:59:59' do
    expect(described_class.today_end).to eq(Time.zone.local(2026, 8, 27, 23, 59, 0))
    expect(described_class.today_end.sec).to eq(0)
  end

  it 'min e max são meia-noite ± 2000 anos' do
    expect(described_class.min.year).to eq(26)
    expect(described_class.max.year).to eq(4026)
    expect(described_class.min).to eq(described_class.today_start - 2000.years)
  end

  it 'unbounded cobre qualquer data plausível do sistema' do
    faixa = described_class.unbounded

    expect(faixa).to cover(Time.zone.local(1998, 1, 1))
    expect(faixa).to cover(Time.zone.local(2199, 12, 31))
  end

  # São MÉTODOS e não constantes congeladas no boot — o legado também
  # recalculava a cada chamada. Um processo de longa duração que congelasse o
  # valor no boot passaria a filtrar pelo dia errado depois da meia-noite.
  it 'recalcula a cada chamada: depois da meia-noite, o dia é outro' do
    ontem = described_class.today_start

    # Sem bloco: o `around` daqui ja congelou o relogio, e `travel_to` com bloco
    # sobre outro `travel_to` levanta RuntimeError de proposito.
    travel_to(Time.zone.local(2026, 8, 28, 0, 0, 1))

    expect(described_class.today_start).to eq(ontem + 1.day)
  end
end
