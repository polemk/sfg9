# frozen_string_literal: true

# Isola o Sidekiq desta app usando APP_NAME como prefixo nas filas.
# Permite N apps compartilhando o mesmo Redis sem colisão de jobs.
redis_config = {
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
  timeout: 15
}

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
