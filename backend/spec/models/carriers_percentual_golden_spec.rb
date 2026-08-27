# frozen_string_literal: true

require 'rails_helper'

# S3 / **DEC-30** — o **golden** do "% de contas subordinadas".
#
# > "O teste não existe para provar que a fórmula está certa — existe para
# > **reprovar quem 'consertar' depois** sem passar por uma DEC."
#
# **A fórmula do legado divide pelas cotas SÊNIOR, não pelo total.** Extraída
# literalmente de `../sfg/app/views/pub/console/parts/carriers/helper/_body.js.erb:47`:
#
#     var prct = senior_accounts.val() == 0
#                  ? 0
#                  : 100.0 * (parseFloat(subordinated_accounts.val()) /
#                             parseFloat(senior_accounts.val()));
#     subordinated_accounts_percent.val(prct.toFixed(2)…);
#
# Isso **não** é a proporção usual de cota subordinada num FIDC
# (subordinada ÷ (sênior + subordinada)), e é exatamente por isso que este
# arquivo existe: quem chegar depois vai olhar `250/750 = 33,33%` e achar que
# são 25%. Com 1.842 sênior e 341 subordinadas o legado mostra **18,51%**; a
# fórmula "certa" mostraria 15,62%. São dois números diferentes na mesma tela,
# e o cliente lê o primeiro há anos.
#
# Para mudar isto é preciso uma DEC nova. Este spec falha antes.
RSpec.describe 'Golden — % de contas subordinadas (DEC-30)', type: :model do
  # Entrada → saída, computadas pela fórmula do legado.
  # `[sênior, subordinadas, percentual esperado]`
  GOLDEN = [
    # As cinco contrapartes do seed de demonstração.
    [1_842, 341, '18.51'],
    [964,   272, '28.22'],
    [713,   238, '33.38'],
    [0,     0,   '0.0'],
    # A guarda de divisão por zero, que no legado só existia no JS.
    [0,     500, '0.0'],
    # Casos de mesa.
    [750,   250, '33.33'],
    [800,   200, '25.0'],
    [800,   600, '75.0'],
    [100,   100, '100.0'],
    [3,     1,   '33.33']
  ].freeze

  GOLDEN.each do |senior, subordinadas, esperado|
    it "#{senior} sênior e #{subordinadas} subordinadas → #{esperado}%" do
      carrier = Carrier.create!(title: "Golden #{senior}-#{subordinadas}",
                                senior_accounts: senior, subordinated_accounts: subordinadas)

      expect(carrier.subordinated_accounts_percent.to_s).to eq(esperado)
    end
  end

  it 'a fórmula divide pelas SÊNIOR — e NÃO pelo total (o "conserto" que este golden reprova)' do
    carrier = Carrier.create!(title: 'Divisor', senior_accounts: 750, subordinated_accounts: 250)

    pelo_total = (BigDecimal('250') * 100 / 1_000).round(2) # 25.0
    expect(carrier.subordinated_accounts_percent).not_to eq(pelo_total)
    expect(carrier.subordinated_accounts_percent).to eq(BigDecimal('33.33'))
  end

  it 'o valor é RECALCULADO a cada gravação, nunca lido do payload' do
    carrier = Carrier.create!(title: 'Recalcula', senior_accounts: 100, subordinated_accounts: 10)
    expect(carrier.subordinated_accounts_percent).to eq(BigDecimal('10.0'))

    # Mesmo escrevendo direto no atributo, o callback vence.
    carrier.subordinated_accounts_percent = 99
    carrier.save!
    expect(carrier.reload.subordinated_accounts_percent).to eq(BigDecimal('10.0'))
  end

  it 'sênior zero NÃO levanta e NÃO grava Infinity/NaN (D-10, no SERVIDOR)' do
    carrier = nil
    expect { carrier = Carrier.create!(title: 'Sem sênior', senior_accounts: 0, subordinated_accounts: 42) }
      .not_to raise_error

    valor = carrier.reload.subordinated_accounts_percent
    expect(valor).to eq(0)
    expect(valor).to be_finite
  end
end
