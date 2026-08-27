# frozen_string_literal: true

AI9::Application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.public_file_server.enabled = true
  config.public_file_server.headers = { 'Cache-Control' => 'public, max-age=3600' }
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = false
  config.action_controller.allow_forgery_protection = false
  config.action_mailer.perform_caching = false

  # S13 — **a suíte estava tentando falar SMTP de verdade.**
  #
  # `test.rb` declarava `perform_caching` e mais nada de e-mail, e o default do Rails
  # para `delivery_method` é `:smtp`. Consequência medida: qualquer exemplo que
  # dispare um mailer trava ~7 s por tentativa e morre com `Net::OpenTimeout` — e
  # num ambiente com SMTP alcançável **mandaria e-mail de verdade a partir do teste**,
  # inclusive código de acesso, que é credencial (DEC-14/DEC-90).
  #
  # `:test` acumula as mensagens em `ActionMailer::Base.deliveries`, que é onde os
  # exemplos as conferem. `raise_delivery_errors` fica ligado de propósito: é o que
  # permite testar o caminho de FALHA de entrega (DB-481) — com ele desligado o erro
  # some e o log de falha nunca seria exercitado.
  config.action_mailer.delivery_method = :test
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = { host: 'test.host' }
  # Sem cache real em teste: evita vazamento de estado entre exemplos.
  config.cache_store = :null_store
  config.active_support.deprecation = :stderr
  config.action_cable.url = 'ws://localhost:3000/cable'
  config.action_cable.allowed_request_origins = ['http://localhost:5173', 'http://localhost:3000']
  config.action_cable.disable_request_forgery_protection = true
  config.active_job.queue_adapter = :inline
  config.active_storage.service = :test
end
