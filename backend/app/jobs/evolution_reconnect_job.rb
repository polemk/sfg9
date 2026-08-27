# frozen_string_literal: true

# Monitora e reconecta a instância Evolution quando desconectada.
# Disparado automaticamente pelo WhatsAppWebhookService ao detectar
# status refused/unknown. Re-agenda até MAX_ATTEMPTS vezes.
class EvolutionReconnectJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 5
  RETRY_INTERVAL = 3.minutes

  def perform(attempt = 1)
    status_response = EvolutionConnection.instance_connect_status
    state = status_response.dig(:response, 'instance', 'state') ||
            status_response.dig(:response, 'state')

    Rails.logger.info("[EvolutionReconnect] Estado: #{state} (tentativa #{attempt}/#{MAX_ATTEMPTS})")

    if state == 'open'
      Rails.logger.info('[EvolutionReconnect] Instância já conectada.')
      return
    end

    Rails.logger.warn("[EvolutionReconnect] Desconectada (#{state}), chamando restart...")
    EvolutionConnection.restart_instance

    if attempt < MAX_ATTEMPTS
      self.class.set(wait: RETRY_INTERVAL).perform_later(attempt + 1)
    else
      Rails.logger.error("[EvolutionReconnect] #{MAX_ATTEMPTS} tentativas esgotadas — intervenção manual necessária.")
    end
  rescue StandardError => e
    Rails.logger.error("[EvolutionReconnect] Erro: #{e.message}")
    self.class.set(wait: RETRY_INTERVAL).perform_later(attempt + 1) if attempt < MAX_ATTEMPTS
  end
end
