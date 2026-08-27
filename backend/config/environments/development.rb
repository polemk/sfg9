# frozen_string_literal: true

AI9::Application.configure do
  # Reload código a cada requisição; ideal para desenvolvimento
  config.cache_classes = false
  config.eager_load = false

  # Exibe erros completos em desenvolvimento
  config.consider_all_requests_local = true

  # Cache (Redis) para paridade com produção
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
    namespace: 'cache_dev'
  }

  # Fila de jobs
  config.active_job.queue_adapter = :sidekiq

  # Action Cable (WebSocket)
  config.action_cable.url = ENV.fetch('ACTION_CABLE_URL', 'ws://localhost:3000/cable')
  config.action_cable.allowed_request_origins = ENV.fetch('CORS_ORIGINS', 'http://localhost:5173,http://localhost:5174,http://localhost:3000').split(',')
  config.action_cable.disable_request_forgery_protection = true

  config.action_dispatch.cookies_same_site_protection = ENV.fetch('COOKIES_SAME_SITE', 'lax').to_sym

  config.active_storage.service = :local

  # Logs detalhados com request_id; saída em STDOUT quando configurado
  config.log_level = :debug
  config.log_tags = [:request_id]
  if ENV['RAILS_LOG_TO_STDOUT'].present?
    logger = ActiveSupport::Logger.new($stdout)
    logger.formatter = Logger::Formatter.new
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # Servir arquivos estáticos em dev quando necessário (Swagger JSON, etc.)
  config.public_file_server.enabled = true

  # Configuração Action Mailer (SMTP real em dev)
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = {
    host: ENV.fetch('APP_HOST', 'http://localhost:5173').gsub(%r{https?://}, ''),
    protocol: ENV.fetch('APP_HOST', 'http://localhost:5173').start_with?('https') ? 'https' : 'http'
  }
  config.action_mailer.smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', 'localhost'),
    port: ENV.fetch('SMTP_PORT', 587).to_i,
    domain: ENV.fetch('SMTP_DOMAIN', 'polemk.com'),
    user_name: ENV.fetch('SMTP_USERNAME', ''),
    password: ENV.fetch('SMTP_PASSWORD', ''),
    authentication: ENV.fetch('SMTP_AUTHENTICATION', 'login').to_s.downcase.to_sym,
    enable_starttls_auto: ENV.fetch('SMTP_TLS_ENABLED', 'true') == 'true',
    # OPS-626 / C-05: verificação de certificado ATIVA por padrão. O legado desligava
    # `VERIFY_PEER` globalmente no Windows (`config/initializers/ssl_for_win.rb:1`) e a
    # própria base ai9 repetia o defeito aqui com `openssl_verify_mode: 'none'` — sem a
    # desculpa de plataforma. Quem tem SMTP com certificado interno usa a ENV.
    openssl_verify_mode: ENV.fetch('SMTP_OPENSSL_VERIFY_MODE', 'peer'),
    open_timeout: 10,
    read_timeout: 10
  }

  # Facilita desenvolvimento local/WSL com diferentes hosts
  config.hosts.clear
end
