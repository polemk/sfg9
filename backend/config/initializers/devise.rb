# frozen_string_literal: true

require 'devise/orm/active_record'
Devise.setup do |config|
  config.mailer_sender = ENV.fetch('DEVISE_MAILER_FROM', 'no-reply@ai9.local')
  config.secret_key = Rails.application.credentials.secret_key_base
  config.omniauth_path_prefix = '/users/auth'
  OmniAuth.config.path_prefix = '/users/auth'

  config.jwt do |jwt|
    jwt.secret = ENV['DEVISE_JWT_SECRET_KEY'] || ENV['JWT_SECRET'] || Rails.application.credentials.secret_key_base
    jwt.expiration_time = ENV.fetch('JWT_EXPIRATION_TIME_MINUTES', '15').to_i.minutes.to_i
    jwt.dispatch_requests = []
    jwt.revocation_requests = []
    jwt.request_formats = { user: [:json] }
  end

  config.omniauth :google_oauth2,
                  Rails.application.credentials.dig(:oauth, :google, :client_id),
                  Rails.application.credentials.dig(:oauth, :google, :client_secret),
                  {
                    redirect_uri: ENV['OAUTH_GOOGLE_REDIRECT_URI'] || ENV['OAUTH_REDIRECT_URI']
                  }

  # OPS-605 — login social do Facebook permanece DESLIGADO, agora como flag booleana
  # em vez de configuracao morta.
  #
  # No legado o Facebook estava configurado e nao levava a lugar nenhum: chave
  # presente, botao ausente. Aqui a estrategia so e REGISTRADA quando
  # `OAUTH_FACEBOOK_ENABLED=true`; com o default (`false`) o provedor nao existe no
  # OmniAuth, e `/users/auth/facebook` responde 404 em vez de iniciar um fluxo que
  # ninguem termina. Configuracao morta e pior que ausencia: ela sugere que existe.
  #
  # O descarte do mecanismo legado e o OPS-489, de S13.
  if ENV.fetch('OAUTH_FACEBOOK_ENABLED', 'false') == 'true'
    config.omniauth :facebook,
                    Rails.application.credentials.dig(:oauth, :facebook, :app_id),
                    Rails.application.credentials.dig(:oauth, :facebook, :app_secret),
                    {
                      redirect_uri: ENV['OAUTH_FACEBOOK_REDIRECT_URI'] || ENV['OAUTH_REDIRECT_URI']
                    }
  end
end
