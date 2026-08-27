# frozen_string_literal: true

# Limpa login_codes expirados ou usados há mais de 24h.
# Executar periodicamente via:
#   CleanupLoginCodesJob.perform_later
# Ou agendar via sidekiq-cron / whenever:
#   every 1.hour: CleanupLoginCodesJob.perform_later
class CleanupLoginCodesJob < ApplicationJob
  queue_as :default

  def perform
    deleted_expired = LoginCode.expired.delete_all
    deleted_used    = LoginCode.used.where('used_at < ?', 24.hours.ago).delete_all

    Rails.logger.info("[CleanupLoginCodesJob] Removidos: #{deleted_expired} expirados, #{deleted_used} usados antigos")
  end
end
