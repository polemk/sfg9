# Procfile de PRODUÇÃO — OPS-476, OPS-461, OPS-633.
#
# **O que o legado declarava:** só `server` e `assets`. O worker do `delayed_job` era
# subido à mão, por um daemon com pidfile (`bin/delayed_job`), fora do supervisor do
# processo. Consequências: se o worker morresse, nada o levantava de volta e nada
# denunciava a ausência — os jobs simplesmente paravam de rodar, em silêncio. E se o
# pidfile ficasse órfão depois de um kill, o daemon se recusava a subir de novo.
#
# **Aqui não há daemon nem pidfile.** Os dois processos são declarados e o supervisor
# da plataforma os mantém de pé.
#
# **Não existe processo de agendador.** O `sidekiq-cron` roda DENTRO do processo
# Sidekiq: `config/initializers/sidekiq_cron.rb` carrega `config/schedule.yml` no
# `on(:startup)` do servidor. Um terceiro processo só de cron seria mais uma coisa
# para esquecer de subir — e ele foi justamente o que faltou na base ai9, onde o
# agendamento só existia em chaves do Redis (upstream-flags #13).
#
# ⚠ `worker` precisa de `-C config/sidekiq.yml`: é o arquivo que declara AS FILAS.
# Sem ele o Sidekiq consome só `default` — sem prefixo — e todo job das filas
# `<APP_NAME>_*` fica empilhado para sempre, sem erro nenhum.
web: cd backend && bundle exec puma -C config/puma.rb
worker: cd backend && bundle exec sidekiq -C config/sidekiq.yml
