# frozen_string_literal: true

require_relative 'boot'
if ENV['RAILS_ENV'] == 'test'
  require 'active_model/railtie'
  require 'active_job/railtie'
  require 'active_record/railtie'
  require 'action_controller/railtie'
  require 'action_mailer/railtie'
  require 'action_view/railtie'
  require 'action_cable/engine'
  require 'active_storage/engine'
  require 'action_text/engine'
else
  require 'rails/all'
end

Bundler.require(*Rails.groups)

module AI9
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.middleware.insert_before 0, Rack::Cors


    # Configuration for the application
    config.time_zone = 'Brasilia'
    config.i18n.default_locale = :'pt-BR'
    config.i18n.available_locales = %i[pt-BR en]
    config.i18n.fallbacks = { 'pt-BR' => [:en] }

    # Enable cookies and sessions (required by OmniAuth)
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
                          key: ENV.fetch('SESSION_KEY', '_ai9_session'),
                          secure: ENV.fetch('SESSION_SECURE', 'false') == 'true',
                          same_site: ENV.fetch('COOKIES_SAME_SITE', 'lax').to_sym

    # Active Job configuration
    config.active_job.queue_adapter = :sidekiq
    config.active_job.queue_name_prefix = ENV.fetch('APP_NAME', 'ai9')
    config.active_job.queue_name_delimiter = '_'

    # Action Cable configuration
    config.action_cable.mount_path = '/cable'
    config.action_cable.url = ENV.fetch('ACTION_CABLE_URL', 'ws://localhost:3000/cable')
    config.action_cable.allowed_request_origins = ENV
                                                  .fetch('CORS_ORIGINS', 'http://localhost:5173,http://localhost:3000,https://app.ai9.com.br')
                                                  .split(',')
  end
end
