# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/seeds/demo/ledger').to_s
require Rails.root.join('db/seeds/demo/reset').to_s
require Rails.root.join('db/seeds/demo/writers/carriers').to_s

# **O contador de portadores depois de dois ciclos de `demo:reseed`.**
#
# O defeito que este arquivo tranca foi medido na tela, não no código: em
# 26/08/2026 `/carrier-groups` mostrava **7 / 7 / 7 / 14** onde o banco tinha
# **1 / 1 / 1 / 2** — 35 portadores declarados para os 5 que existem. Cada ensaio
# da apresentação somava mais uma rodada, porque `Reset#drop_carriers` usava
# `delete_all`, que **não passa por callback** e portanto não decrementa o
# `counter_cache` de `Carrier#group` (`app/models/carrier.rb:36-37`).
#
# **Por que um spec e não uma conferência à mão:** a suíte inteira estava verde
# com o defeito no lugar. O único jeito de um `counter_cache` divergir é alguém
# escrever fora do callback, e o único jeito de isso aparecer em teste é o teste
# **rodar o ciclo duas vezes** — uma execução só nunca infla nada.
#
# O critério é sempre `contador == contagem real`, nunca um número literal: assim
# o spec continua valendo no dia em que o razão ganhar uma contraparte nova.
RSpec.describe 'demo:reseed — o contador de portadores não infla' do
  let(:io) { StringIO.new }
  # `span: 2` porque nada aqui depende da série temporal: este spec roda **só** o
  # escritor de portadores e o reset, não o orquestrador inteiro.
  let(:ledger) { Demo::Ledger.new(base_date: Date.new(2026, 8, 28), span: 2) }

  def cache
    CarrierGroup.order(:title).pluck(:title, :carriers_count).to_h
  end

  def real
    CarrierGroup.order(:title).to_h { |grupo| [grupo.title, grupo.carriers.count] }
  end

  it 'o reset zera o contador do grupo junto com os portadores que ele apaga' do
    Demo::Writers::Carriers.new(ledger, io: io).run
    expect(cache.values.sum).to eq(Carrier.count)

    Demo::Reset.new(ledger: ledger, io: io).run

    expect(Carrier.count).to be_zero
    expect(cache.values).to all(be_zero)
  end

  it 'depois de DOIS ciclos reset+seed cada grupo continua declarando a contagem real' do
    2.times do
      Demo::Reset.new(ledger: ledger, io: io).run
      Demo::Writers::Carriers.new(ledger, io: io).run
    end

    # Antes da correção o cache voltava dobrado (2/2/2/4) enquanto o real
    # continuava 1/1/1/2 — e é o cache que decide o botão de excluir.
    expect(cache).to eq(real)
    expect(cache.values.sum).to eq(Carrier.count)
  end

  it 'reconta um grupo que já estava inflado por execuções anteriores do seed' do
    Demo::Writers::Carriers.new(ledger, io: io).run
    grupo = CarrierGroup.order(:title).first
    # É exatamente a defasagem que sete ensaios deixaram no banco de
    # demonstração: coluna alta, tabela intacta.
    CarrierGroup.where(id: grupo.id).update_all(carriers_count: 7)

    Demo::Reset.new(ledger: ledger, io: io).run

    expect(grupo.reload.carriers_count).to be_zero
  end

  # O contrário do defeito: o reset não pode "consertar" um grupo que não é dele
  # apagando ou zerando portador de fora do seed.
  it 'não mexe em portador que não é do seed — só recontabiliza o grupo' do
    Demo::Writers::Carriers.new(ledger, io: io).run
    grupo = CarrierGroup.order(:title).first
    alheio = Carrier.create!(title: 'Portador de fora do seed', bank_code: '999',
                             group_id: grupo.id, senior_accounts: 0,
                             subordinated_accounts: 0, net_worth: 0)

    Demo::Reset.new(ledger: ledger, io: io).run

    expect(Carrier.exists?(id: alheio.id)).to be(true)
    expect(grupo.reload.carriers_count).to eq(1)
  end
end
