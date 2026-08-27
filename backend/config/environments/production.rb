# frozen_string_literal: true

AI9::Application.configure do
  # Performance
  config.middleware.use Rack::Deflater
  config.cache_classes = true
  config.eager_load = true

  # Active Storage — OPS-616 / Q-07 (provedor ainda NAO escolhido).
  #
  # Era `:local`, que grava em `backend/storage/`, dentro da arvore da aplicacao: em
  # qualquer deploy que troque o diretorio os anexos somem, e somem em silencio,
  # porque o registro no banco continua apontando para um blob que nao existe mais.
  # O default agora e `disk_persistent`, que aponta para fora do release
  # (`ACTIVE_STORAGE_DISK_ROOT`). Ver o cabecalho de `config/storage.yml`.
  config.active_storage.service = ENV.fetch('ACTIVE_STORAGE_SERVICE', 'disk_persistent').to_sym


  # Erros não detalhados em produção
  config.consider_all_requests_local = false

  # Cache (Redis)
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
    namespace: 'ai9_cache_prod',
    reconnect_attempts: 1
  }

  # Active Job
  config.active_job.queue_adapter = :sidekiq

  # Logs estruturados
  config.log_level = :info
  config.log_tags = [:request_id]

  # Configuração de Logger Híbrido (Arquivo + STDOUT)
  # Garante que logs vão para log/production.log E para o terminal (Systemd)
  file_logger = ActiveSupport::Logger.new(config.paths["log"].first)
  file_logger.formatter = config.log_formatter

  if ENV['RAILS_LOG_TO_STDOUT'].present?
    stdout_logger = ActiveSupport::Logger.new($stdout)
    stdout_logger.formatter = config.log_formatter
    
    # Rails 7.1+ BroadcastLogger
    broadcast = ActiveSupport::BroadcastLogger.new(file_logger, stdout_logger)
    config.logger = ActiveSupport::TaggedLogging.new(broadcast)
  else
    config.logger = ActiveSupport::TaggedLogging.new(file_logger)
  end

  # Servir arquivos estáticos quando atrás de CDN ou em ambientes simples
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
  config.public_file_server.headers = {
    'Cache-Control' => 'public, max-age=31536000'
  }

  # SSL e segurança
  config.force_ssl = ENV.fetch('FORCE_SSL', 'true') == 'true'
  config.action_dispatch.default_headers = {
    'X-Content-Type-Options' => 'nosniff',
    'X-Frame-Options' => 'DENY',
    'Referrer-Policy' => 'strict-origin-when-cross-origin'
  }

  # Action Cable (WebSocket)
  config.action_cable.url = ENV.fetch('ACTION_CABLE_URL', 'wss://example.com/cable')
  config.action_cable.allowed_request_origins = ENV
                                                .fetch('CORS_ORIGINS', 'https://example.com')
                                                .split(',')

  # Configuração Action Mailer
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = {
    host: ENV.fetch("API_HOST", "api-goat.polemk.com"),
    protocol: "https"
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

  Rails.application.routes.default_url_options = config.action_mailer.default_url_options
  config.action_controller.default_url_options = config.action_mailer.default_url_options

  # I18n fallback
  config.i18n.fallbacks = true

  # Deprecations
  config.active_support.report_deprecations = false

  config.action_dispatch.cookies_same_site_protection = ENV.fetch('COOKIES_SAME_SITE', 'lax').to_sym
end
