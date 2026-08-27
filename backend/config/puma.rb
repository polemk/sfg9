# frozen_string_literal: true

# Puma — OPS-631.
#
# No legado `config/puma.rb` fixava `RAILS_ENV` em `development`. Em produção isso
# significa código recarregável a cada requisição, log verboso e o `secret_key_base`
# de desenvolvimento (que, no legado, ainda por cima estava commitado). Aqui o
# ambiente vem do ambiente, que é a única fonte que o deploy controla.

max_threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
min_threads_count = ENV.fetch('RAILS_MIN_THREADS') { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch('PORT', 3026)

environment ENV.fetch('RAILS_ENV', 'development')

pidfile ENV.fetch('PIDFILE', 'tmp/pids/server.pid')

# Modo cluster: configurável, e desligado por padrão.
#
# `WEB_CONCURRENCY=0` (o default) mantém um processo só — que é o que desenvolvimento
# quer, porque worker forkado quebra o `byebug` e o reload. Em produção o valor sai do
# ambiente, junto com o `preload_app!`, sem o qual cada worker carrega a aplicação
# inteira de novo e o ganho de memória do fork se perde.
workers_count = ENV.fetch('WEB_CONCURRENCY', 0).to_i
if workers_count.positive?
  workers workers_count
  preload_app!

  # Cada worker precisa da sua própria conexão: herdar o socket do processo pai é o
  # jeito clássico de ver `PG::UnableToSend` sob carga.
  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
  end
end

plugin :tmp_restart
