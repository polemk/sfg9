# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/seeds/demo/ledger').to_s

# Spec do **razão** do seed de demonstração (S20 / DEC-64).
#
# Roda sem tocar no banco e **sem nenhum model de domínio existir** — que é
# exatamente a situação em que esta fatia nasceu (S3..S11 rodam depois dela).
# É isso que torna as 7 regras de coerência verificáveis hoje, em vez de na
# véspera da demonstração.
#
# `demo-seed-design.md` §12: *"Seed que gera número incoerente é bug, não 'dado
# de exemplo'."* Este arquivo é onde isso é imposto.
RSpec.describe Demo::Ledger do
  # Data-base fixa **só aqui**: o razão usa `Date.current` na vida real, e o
  # teste precisa de um ponto de referência estável para as asserções de série
  # temporal.
  let(:base_date) { Date.new(2026, 8, 28) }
  let(:ledger) { described_class.new(base_date: base_date) }

  # Os borderôs do mesmo cliente e do mesmo mês da entrada de indicador — a
  # lista que a tela mostra quando alguém clica no ponto do gráfico.
  def borderos_of(entry)
    ledger.borderos.select do |b|
      b.client.slug == entry.client.slug &&
        b.month.year == entry.year && b.month.month == entry.month
    end
  end

  describe 'regra 1 — a aritmética fecha' do
    it 'o saldo de cada operação é o acumulado dos movimentos na ordem de sequence' do
      divergent = ledger.operations.reject do |operation|
        accumulated = operation.movements.sort_by(&:sequence).sum do |movement|
          movement.credit_type == 'D' ? -movement.value : movement.value
        end
        (accumulated - operation.balance).abs < 0.02
      end

      expect(divergent).to be_empty
    end

    # **O saldo nunca fica positivo, em nenhum ponto da cadeia.** Não é
    # preciosismo: `balance_on` lê o último movimento ATÉ a data pedida, então um
    # saldo positivo no meio do caminho vira **exposição negativa** no painel de
    # risco — foi o que apareceu na tela (`-1,41%` de um limite) quando a
    # liquidação de uma operação encerrada estava datada antes do lançamento de
    # juros. A soma final estava certa; o meio, não.
    it 'nenhum saldo intermediário fica positivo — a operação nunca é credora' do
      credoras = ledger.operations.reject do |operation|
        operation.movements.all? { |m| m.balance <= 0.01 }
      end

      expect(credoras).to be_empty
    end

    it 'a última liquidação zera a operação encerrada' do
      ended = ledger.operations.select { |o| o.state == :ended }

      expect(ended).to be_present
      expect(ended.map(&:balance)).to all(be_within(0.005).of(0))
    end

    it 'o valor final do borderô é o bruto menos o recusado' do
      expect(ledger.borderos).to all(
        satisfy { |b| ((b.valor_bruto - b.vlr_bruto_recusado) - b.vlr_bruto_final).abs < 0.005 }
      )
    end

    it 'a quantidade final do borderô é a quantidade menos a recusada' do
      expect(ledger.borderos).to all(
        satisfy { |b| b.qtd_titulos - b.qtd_recusada == b.qtd_final }
      )
    end

    it 'a diferença de float é a subtração, e não um terceiro sorteio' do
      expect(ledger.borderos).to all(
        satisfy { |b| b.diferenca_float == b.float_calculado - b.float_acordado }
      )
    end

    it 'as parcelas de uma renegociação somam o total, e o restante é o total menos o pago' do
      # As duas renegociações de vitrine ficam de fora **por construção**: uma
      # não tem parcela e a outra tem parcelas de menos, que é o que faz os
      # estados "Sem parcela cadastrada" e "Inconsistente" existirem na tela.
      regulares = ledger.renegotiations.reject { |r| r.installments.empty? }
                                       .reject { |r| r.state == 'Inconsistente' }

      expect(regulares).to all(
        satisfy do |r|
          (r.installments.sum(&:main_value) - r.total_debt).abs < 0.02 &&
            # As três parcelas do cadastro somam a dívida: o vencido
            # (`original_value`), o a vencer (`original_pending_value`) e as
            # despesas (`additional_value`). O vencido entrou quando a S9
            # entregou a tabela com a coluna — antes disto ele não existia no
            # razão, e o campo da tela ficava zerado em todas as renegociações.
            ((r.original_value + r.original_pending_value + r.additional_value) -
              r.total_debt).abs < 0.005 &&
            # **"R$ A Pagar" é a soma do que as parcelas ainda devem**, e não
            # `total − pago`. As duas contas divergem, de propósito: "R$ Pago"
            # conta juros e mora e "R$ A Pagar" não (Q-B22/Q-B26), então
            # `total − pago` fica menor que o principal em aberto pelo exato
            # valor dos juros já pagos. Quem manda é
            # `Renegotiations::Formulas.aggregate`, e o razão agora o espelha —
            # antes ele usava a subtração, e o número do razão nunca teria
            # batido com o que o serviço da S9 grava.
            r.remaining_value >= 0 &&
            (r.installments.sum(&:main_value) -
              (r.installments.select(&:is_paid).sum(&:main_value) + r.remaining_value)).abs < 0.02
        end
      )
    end

    it 'pagas mais atrasadas nunca passam do total de parcelas' do
      expect(ledger.renegotiations).to all(
        satisfy { |r| r.paid_installments + r.overdue_installments <= r.installments_count }
      )
    end
  end

  describe 'regra 2 — nada de número redondo' do
    it 'nenhum limite de controle é múltiplo de mil' do
      expect(ledger.controls.map(&:limite)).to all(satisfy { |v| (v % 1000) != 0 })
    end

    it 'nenhum valor bruto de borderô é múltiplo de mil' do
      expect(ledger.borderos.count { |b| (b.valor_bruto % 1000).zero? }).to be_zero
    end
  end

  describe 'regra 3 — faixas de mercado' do
    it 'as taxas dos controles ficam entre 1,0% e 3,5% ao mês' do
      expect(ledger.controls.map(&:taxa)).to all(be_between(1.0, 3.5))
    end

    it 'a taxa da operação não se afasta mais de 0,15 p.p. da taxa do controle' do
      # Operação a 2,1% num controle de 3,0% é a incoerência que quem é do
      # mercado enxerga na primeira linha da tela.
      expect(ledger.operations).to all(
        satisfy { |o| (o.agreed_rate - o.control.taxa).abs <= 0.1501 }
      )
    end

    it 'o IOF segue a regra de crédito PJ (0,0082%/dia limitado a 365 + 0,38%)' do
      principal = 100_000.0
      expect(Demo::Support::Money.iof(principal, 60)).to be_within(0.01).of(872.0)
      expect(Demo::Support::Money.iof(principal, 400))
        .to eq(Demo::Support::Money.iof(principal, 365))
    end
  end

  describe 'regra 4 — distribuição com cauda' do
    it 'o maior cliente opera pelo menos 10 vezes o volume do menor' do
      volumes = ledger.clients.map do |client|
        ledger.borderos.select { |b| b.client.slug == client.slug }.sum(&:vlr_bruto_final)
      end

      expect(volumes.max / volumes.min).to be >= 10
    end
  end

  describe 'regra 5 — história no tempo' do
    it 'dezembro fica abaixo da média mensal' do
      by_month = ledger.months.to_h do |month|
        [month.offset, ledger.borderos.select { |b| b.month.offset == month.offset }.sum(&:vlr_bruto_final)]
      end
      average = by_month.values.sum / by_month.size

      ledger.months.select { |m| m.month == 12 }.each do |december|
        expect(by_month[december.offset]).to be < average
      end
    end

    it 'a série termina acima de onde começou' do
      first = ledger.borderos.select { |b| b.month.offset == -23 }.sum(&:vlr_bruto_final)
      last = ledger.borderos.select { |b| b.month.offset.zero? }.sum(&:vlr_bruto_final)

      expect(last).to be > first
    end

    it 'o cliente recém-entrante só tem histórico dos últimos meses' do
      entrante = ledger.clients.find { |c| c.story == :entrante }
      offsets = ledger.borderos.select { |b| b.client.slug == entrante.slug }.map { |b| b.month.offset }

      expect(offsets.min).to be >= entrante.active_from
      expect(offsets.uniq.size).to be <= 3
    end
  end

  describe 'regra 6 — estados misturados' do
    it 'convivem operações encerradas, vivas e vencidas' do
      by_state = ledger.operations.group_by(&:state).transform_values(&:size)

      expect(by_state.keys).to match_array(%i[ended live overdue])
      expect(by_state.values).to all(be_positive)
    end

    # **O que faz a lista ter cor.** Um estado que a tela sabe pintar e que o
    # banco nunca tem é um filtro que devolve vazio na frente do cliente — e,
    # no caso de "Inconsistente", é um conserto da S9 (D-45) que ninguém vê.
    it 'os quatro estados de renegociação têm pelo menos um exemplo cada' do
      states = ledger.renegotiations.group_by(&:state).transform_values(&:size)

      # A lista é escrita à mão, e não lida de `Renegotiation::STATES`, porque
      # este spec roda **sem nenhum model de domínio** — é essa independência que
      # deixa o razão ser testado antes de a fatia dona entregar.
      expect(states.keys).to match_array(['Liquidado', 'Pago', 'Inconsistente',
                                          'Sem parcela cadastrada'])
      expect(states.values).to all(be_positive)
    end

    it 'a maioria dos borderôs não tem recusa, e nenhum passa de 12%' do
      without = ledger.borderos.count { |b| b.qtd_recusada.zero? }

      expect(without).to be > (ledger.borderos.size * 0.6)
      expect(ledger.borderos).to all(
        satisfy { |b| b.vlr_bruto_recusado <= (b.valor_bruto * 0.1201) }
      )
    end
  end

  describe 'regra 7 — volume que justifica a interface' do
    it 'os 12 clientes dão duas páginas de Kaminari a 10 por página' do
      expect(ledger.clients.size).to eq(12)
      expect((ledger.clients.size / 10.0).ceil).to eq(2)
    end

    # **As faixas subiram na passada de cobertura de 26/08/2026** (§14 do
    # desenho). O alvo original — ~28 empresas, ~70 limites — deixava quatro
    # clientes com UMA empresa e UM limite, e medido na tela isso não demonstra
    # nada: sem duas empresas a consolidação do painel de disponibilidade repete
    # a linha da empresa única, e com um limite só a tela de Limites não tem
    # carteira para comparar. Onze dos doze passaram a ter duas ou mais de cada.
    it 'a volumetria fica na ordem de grandeza do desenho' do
      expect(ledger.companies.size).to be_between(32, 40)
      expect(ledger.controls.size).to be_between(85, 115)
      expect(ledger.borderos.size).to be > 2_000
      expect(ledger.operations.size).to be > 500
      expect(ledger.indicator_entries.size).to be > 1_400
    end
  end

  describe 'a cadeia entre domínios' do
    # **O consumo por limite medido COMO O SISTEMA MEDE.**
    #
    # Este bloco já foi corrigido uma vez — de "todas as vivas" para "as vivas na
    # janela da data-base" — e ainda estava errado por baixo: ele somava
    # `-o.balance`, o saldo do **razão**, que parte de zero e empurra o débito
    # para baixo. A cadeia do sistema é a **oposta**: parte de `original_balance`
    # (negativo) e o movimento de Liberação do Recurso cancela o principal, de
    # forma que `limite_utilizado_on` sai como `Σ liquidações − Σ encargos`
    # (`legacy-defects.md` **D-B20**, DEC-01/DEC-30).
    #
    # Consequência medida no `sfg9_dev`: o razão dizia 92% e os 96 limites do
    # banco estavam **todos** em 0–30%, com máximo de 16,0%. É o mesmo modo de
    # falha de antes, uma camada mais fundo — por isso o spec agora chama
    # `Operations.legacy_exposure`, que é a fórmula do sistema replicada, em vez
    # de reimplementar uma terceira.
    let(:exposure_by_control) do
      ledger.operations
            .group_by(&:control)
            .transform_values do |ops|
              ops.sum { |o| Demo::Ledger::Operations.legacy_exposure(o, base_date) }
            end
    end

    it 'o consumo de limite cobre a faixa inteira, e não só a folgada' do
      faixas = Hash.new(0)
      exposure_by_control.each do |control, used|
        pct = used / control.limite * 100
        faixas[:acima] += 1 if pct > 100
        faixas[:colado] += 1 if pct.between?(90, 100)
        faixas[:atencao] += 1 if pct >= 70 && pct < 90
      end

      # Sem isto o cartão "Limites no teto" da tela inicial só sabe dizer zero, e
      # zero permanente não distingue "não há estouro" de "a conta quebrou".
      #
      # O teto de estouros é **baixo de propósito**: base inteira estourada é
      # cenário, não demonstração. Ver `Controls::UTILIZATION_PLAN`.
      expect(faixas[:acima]).to be_between(1, 4)
      expect(faixas[:colado]).to be >= 6
      expect(faixas[:atencao]).to be >= 2
    end

    it 'o estouro fica em três clientes, e em um limite de cada' do
      exceeded = exposure_by_control.select { |control, used| used > control.limite }

      expect(exceeded.keys.map { |c| c.client.slug }.tally)
        .to eq('alianca-metalurgica' => 1, 'nordeste-alimentos' => 1, 'serra-azul-textil' => 1)
    end

    # **A regra que este exemplo protege é de APRESENTAÇÃO.** Medido em
    # 27/08/2026 pelos serviços do próprio sistema: 10 dos 12 projetos davam
    # `0` e `0` nos dois indicadores da DEC-116, e quem abrisse qualquer projeto
    # que não fosse um dos dois maiores via zero de novo.
    #
    # A contrapartida está no exemplo seguinte: alguns clientes **precisam**
    # continuar sem nada, senão a carteira inteira parece um desastre.
    it 'a maioria dos clientes tem ao menos um limite de 90% para cima' do
      com_aperto = exposure_by_control.filter_map do |control, used|
        control.client.slug if used / control.limite >= 0.90
      end.uniq

      expect(com_aperto.size * 2).to be > ledger.clients.size
    end

    it 'e pelo menos dois clientes NÃO têm nenhum — o contraste' do
      apertados = exposure_by_control.filter_map do |control, used|
        control.client.slug if used / control.limite >= 0.90
      end.uniq

      folgados = ledger.clients.map(&:slug) - apertados

      expect(folgados.size).to be >= 2
    end

    it 'todo limite do plano de utilização chega ao alvo' do
      planejados = ledger.controls.select do |c|
        (c.target_utilization || 0) >= Demo::Ledger::Controls::FORCED_UTILIZATION_FLOOR
      end

      expect(planejados).not_to be_empty
      planejados.each do |control|
        real = exposure_by_control.fetch(control, 0.0) / control.limite
        expect(real).to be_within(0.02).of(control.target_utilization)
      end
    end

    it 'o indicador de volume operado é a soma dos borderôs do mesmo mês' do
      # **É a prova de que o painel e a lista mostram o mesmo número.** Painel que
      # não bate com a lista que o gerou é, numa demo comercial, pior que tela
      # vazia — o cliente confere a conta.
      volume = ledger.indicator_entries.select { |e| e.indicator_key == 'volume_operado' }
      divergent = volume.reject do |entry|
        total = borderos_of(entry).sum(&:vlr_bruto_final)
        (total - entry.value).abs < 0.02
      end

      expect(divergent).to be_empty
    end

    it 'o índice de recusa do mês é a razão entre recusado e bruto dos mesmos borderôs' do
      entry = ledger.indicator_entries.find do |e|
        e.indicator_key == 'indice_recusa' && e.value.positive?
      end
      batch = borderos_of(entry)
      expected = (batch.sum(&:vlr_bruto_recusado) / batch.sum(&:valor_bruto) * 10_000).round / 100.0

      expect(entry.value).to be_within(0.01).of(expected)
    end
  end

  describe 'plausibilidade do dado brasileiro' do
    it 'todo CNPJ tem os dois dígitos verificadores válidos' do
      expect(ledger.companies.map(&:cnpj)).to all(satisfy { |c| Demo::Support::Br.valid_cnpj?(c) })
    end

    it 'as empresas de um grupo compartilham a raiz de 8 dígitos' do
      ledger.companies.group_by { |c| c.client.slug }.each_value do |companies|
        expect(companies.map { |c| c.cnpj[0, 8] }.uniq.size).to eq(1)
      end
    end

    it 'não há rótulo de teste em nome nenhum' do
      names = ledger.companies.map(&:title) + ledger.clients.map(&:name) + ledger.carriers.map(&:title)

      expect(names).to all(satisfy { |n| n !~ /teste|lorem|empresa \d/i })
    end

    it 'nenhuma contraparte usa código de banco atribuído nem nome de instituição real' do
      # Carrier com nome de banco real, numa demo comercial, sugere relação
      # comercial que não existe.
      assigned = %w[001 033 104 237 341 356 399 422 745 077 260 336]
      real_names = /banco do brasil|bradesco|ita[úu]|santander|caixa econ|crefisa|nubank|inter/i

      expect(ledger.carriers.map(&:bank_code) & assigned).to be_empty
      expect(ledger.carriers.map(&:title)).to all(satisfy { |t| t !~ real_names })
    end

    it 'nenhuma data é fixa: mudar a data-base desloca a série inteira' do
      other = described_class.new(base_date: base_date >> 1)

      expect(other.months.last.month).to eq((base_date >> 1).month)
      expect(other.borderos.map(&:date).max).to be > ledger.borderos.map(&:date).max
    end
  end

  describe 'determinismo' do
    it 'dois razões com a mesma data-base produzem exatamente os mesmos números' do
      # Sem isto, "estava R$ 4,2 mi ontem" vira uma conversa ruim no meio da
      # apresentação.
      other = described_class.new(base_date: base_date)

      expect(other.borderos.map(&:valor_bruto)).to eq(ledger.borderos.map(&:valor_bruto))
      expect(other.operations.map(&:balance)).to eq(ledger.operations.map(&:balance))
      expect(other.controls.map(&:limite)).to eq(ledger.controls.map(&:limite))
    end
  end
end
