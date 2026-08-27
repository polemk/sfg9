# frozen_string_literal: true

# Seed de demonstração — OPS-632 (alvo, S18) / DEC-64 (conteúdo, S20).
#
# O buraco que a DEC-64 fechou, e que este comentário existe para não reabrir:
# S18 criava o alvo vazio, S14 dizia "S14 o **consome**" e S15 também consumia —
# ninguém preenchia. Não aparecia em script de cobertura nenhum porque o seed
# **não tem ID de inventário**: os scripts contam os 1439 IDs e o seed não é um
# deles.
#
# A implementação está em `db/seeds/demo/`:
#
#   ledger.rb      o **razão** — Ruby puro, zero ActiveRecord, gera a história
#                  inteira e é onde a aritmética fecha
#   writers/       um escritor por agregado; cada um **pula com aviso** se o
#                  model dele ainda não existir (S3..S11 rodam depois desta fatia)
#   orchestrator.rb  ordem de dependência, idempotência e relatório
#   reset.rb       apaga só o que este seed cria, pela mesma chave natural
#
# **Separado do seed de produção de propósito**: `db/seeds.rb` não carrega nada
# daqui, e no cutover real o seed de demonstração não roda.
namespace :demo do
  def demo_require!
    require Rails.root.join('db/seeds/demo/orchestrator').to_s
    require Rails.root.join('db/seeds/demo/reset').to_s
  end

  desc 'S20: semeia a base de demonstração (idempotente)'
  task seed: :environment do
    demo_require!
    results = Demo::Orchestrator.new.run

    # **Escritor que falhou faz a tarefa terminar com status ≠ 0.** O
    # orquestrador não deixa um estouro derrubar os outros dezesseis (ver
    # `writers/base.rb`), e é justamente por isso que a falha precisa aparecer
    # aqui: seed que imprime "FALHOU" e sai com 0 é seed que passa despercebido
    # num script de deploy.
    failed = results.select { |r| r.status == :failed }
    abort("\n#{failed.size} escritor(es) falharam: #{failed.map(&:writer).join(', ')}") if failed.any?
  end

  desc 'S20: apaga o que o seed de demonstração criou'
  task reset: :environment do
    demo_require!
    Demo::Reset.new.run
  end

  desc 'S20: reset + seed'
  task reseed: %i[reset seed]

  desc 'S20: o que já está semeado e o que cada módulo pendente aguarda (não escreve nada)'
  task status: :environment do
    demo_require!
    Demo::Orchestrator.new.status
  end

  # A prova de que a cadeia fecha, **sem tocar no banco**. Serve para conferir o
  # razão numa base em que os models de domínio ainda não existem — que é a
  # situação em que esta fatia nasceu.
  desc 'S20: imprime a prova aritmética (um borderô, a operação e o total do painel)'
  task ledger: :environment do
    demo_require!
    ledger = Demo::Ledger.new
    money = Demo::Support::Money

    puts
    puts "Razão do seed — data-base #{ledger.base_date}, semente #{Demo::Support::Rng::SEED}"
    puts '=' * 78
    ledger.summary.each { |key, value| puts format('  %-28<k>s %<v>6d', k: key, v: value) }

    client = ledger.clients.first
    month = ledger.months[-2]
    batch = ledger.borderos.select { |b| b.client.slug == client.slug && b.month.offset == month.offset }
    indicator = ledger.indicator_entries.find do |e|
      e.client.slug == client.slug && e.indicator_key == 'volume_operado' &&
        e.year == month.year && e.month == month.month
    end

    puts
    puts "1) O painel — #{client.name}, #{month.label}"
    puts "   Indicador \"Volume operado\" .......... #{money.brl(indicator.value)}"
    puts
    puts "2) Os borderôs que o produziram (#{batch.size} no mês)"
    batch.sort_by(&:nro).first(4).each do |b|
      puts format('   %<nro>s  %<carrier>-32s bruto %<bruto>16s  recusa %<rec>14s  final %<final>16s',
                  nro: b.nro, carrier: b.carrier.title.slice(0, 32),
                  bruto: money.brl(b.valor_bruto), rec: money.brl(b.vlr_bruto_recusado),
                  final: money.brl(b.vlr_bruto_final))
    end
    puts "   … (#{[batch.size - 4, 0].max} outros)"
    puts format('   %-46s soma dos finais %16s', 'TOTAL', money.brl(batch.sum(&:vlr_bruto_final)))
    puts "   Confere com o painel? #{(batch.sum(&:vlr_bruto_final) - indicator.value).abs < 0.02 ? 'SIM' : 'NÃO'}"

    operation = ledger.operations.find { |o| o.state == :live && o.movements.size >= 5 }
    puts
    puts "3) Uma operação viva e o saldo que os movimentos produzem — #{operation.contract_number}"
    puts "   #{operation.company.title} · #{operation.carrier.title} · #{operation.control.modality}"
    puts format('   Valor da operação %20s   taxa %.4f%% a.m. (controle: %.4f%%)',
                money.brl(operation.operation_value), operation.agreed_rate, operation.control.taxa)
    operation.movements.each do |m|
      puts format('     %<seq>2d  %<date>s  %<type>-24s %<sign>s %<value>16s   saldo %<balance>18s',
                  seq: m.sequence, date: m.date, type: m.type_key, sign: m.credit_type,
                  value: money.brl(m.value), balance: money.brl(m.balance))
    end
    puts format('   Saldo final %26s', money.brl(operation.balance))
    puts format('   Exposição no painel (saldo × −1, DEC-01) %s', money.brl(-operation.balance))

    # **A utilização é medida pela fórmula do SISTEMA** (`legacy_exposure`), não
    # pelo saldo do razão. As duas convenções são opostas — ver o comentário
    # longo em `ledger/operations.rb` —, e foi imprimir a do razão aqui que
    # deixou passar meses de "92% no razão, 14% na tela".
    utilizado = lambda do |c|
      ledger.operations.select { |o| o.control.key == c.key }
            .sum { |o| Demo::Ledger::Operations.legacy_exposure(o, ledger.base_date) }
    end

    control = operation.control
    exposure = utilizado.call(control)
    puts
    puts '4) O limite do controle que rege essa operação'
    puts format('   Limite ..................... %s', money.brl(control.limite))
    puts format('   Limite utilizado ........... %s  (%.1f%%)',
                money.brl(exposure), exposure / control.limite * 100)

    planejados = ledger.controls.select do |c|
      (c.target_utilization || 0) >= Demo::Ledger::Controls::FORCED_UTILIZATION_FLOOR
    end
    puts
    puts '5) Os limites do plano de utilização (§3, princípio 6)'
    planejados.sort_by { |c| -c.target_utilization }.each do |c|
      used = utilizado.call(c)
      puts format('   %-46<k>s alvo %5.1<t>f%%  real %5.1<r>f%% de %<l>s',
                  k: c.key, t: c.target_utilization * 100, r: used / c.limite * 100,
                  l: money.brl(c.limite))
    end

    faixas = Hash.new(0)
    ledger.controls.each do |c|
      pct = utilizado.call(c) / c.limite * 100
      faixa = if pct > 100 then 'acima de 100%'
              elsif pct >= 90 then '90-100%'
              elsif pct >= 70 then '70-90%'
              elsif pct >= 30 then '30-70%'
              else '0-30%'
              end
      faixas[faixa] += 1
    end
    puts
    puts '6) Distribuição do consumo de limite'
    ['0-30%', '30-70%', '70-90%', '90-100%', 'acima de 100%'].each do |faixa|
      puts format('   %-16<f>s %3<n>d limites', f: faixa, n: faixas[faixa])
    end
    puts
  end
end
