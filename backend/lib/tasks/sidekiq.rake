# frozen_string_literal: true

# **`rails sidekiq:health` — tem worker servindo ESTE app?**
#
# Escrita depois de a demonstração travar na frente do cliente: desativar um
# padrão de disponibilidade respondia 202, seis nós ficavam travados e o job
# esperava para sempre, porque **nenhum processo consumia as filas do app de
# desenvolvimento**. Havia um `sidekiq` vivo na máquina — de outro app, noutro
# banco. `pgrep` dizia que sim; a tela dizia que não.
#
# Como subir o worker está em `.migration-ai9/platform-runbook.md`, §4.3.
namespace :sidekiq do
  desc 'Diz se existe worker vivo consumindo as filas deste app (APP_NAME)'
  task health: :environment do
    report = Sfg::WorkerHealth.report

    puts
    puts "Filas deste app (APP_NAME=#{ENV.fetch('APP_NAME', 'ai9')}):"
    report.expected_queues.each { |queue| puts "  · #{queue}" }

    puts
    if report.processes.empty?
      puts 'Processos Sidekiq anunciados no Redis: NENHUM'
    else
      puts 'Processos Sidekiq anunciados no Redis (o Redis é compartilhado entre apps):'
      report.processes.each { |process| puts "  · #{process[:identity]} → #{process[:queues].join(', ')}" }
    end

    puts
    if report.by_redis?
      puts 'OK — todas as filas deste app têm worker (confirmado pelo Redis).'
    elsif report.ok?
      # O heartbeat do Sidekiq é uma chave com TTL de 60 s, e nesta máquina ela
      # some por limpeza ampla de terceiro. Sem esta segunda fonte o diagnóstico
      # diria "sem worker" com o worker rodando.
      puts 'OK — o Redis não anuncia worker deste app, mas a MÁQUINA tem:'
      report.local_workers.each { |w| puts "  · PID #{w[:pid]} (APP_NAME=#{w[:app_name]}), nesta mesma árvore" }
      puts 'Provável limpeza ampla de Redis por outro app apagando o heartbeat ' \
           '(ver `platform-runbook.md` §4.2).'
    else
      aviso = report.foreign_only? ? ' (os processos acima são de OUTRO app — não valem)' : ''
      puts "SEM WORKER para: #{report.missing_queues.join(', ')}#{aviso}"
      puts 'Suba com:  cd backend && bundle exec sidekiq -C config/sidekiq.yml'
      puts '(ou `bin/dev` na raiz, que sobe backend + worker + frontend juntos)'
      # Sai diferente de zero para servir como portão de um script de preparo, e
      # não só como relatório que alguém precisa lembrar de ler.
      abort
    end
  end
end
