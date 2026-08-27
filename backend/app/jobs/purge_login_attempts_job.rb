# frozen_string_literal: true

# DEC-60 — expurgo de `login_attempts` com retenção de 90 dias.
#
# A tabela é da base ai9 (`db/schema.rb:451`) e guarda `ip_address` (`inet`,
# `null: false`) e `user_agent` de TODA tentativa de login, com 9 índices e nenhum
# expurgo. Dado pessoal com retenção infinita é passivo de LGPD — adotado pela base,
# não herdado do legado (o legado não registra tentativa nenhuma).
#
# Agendado em `config/schedule.yml`, nunca pela Web UI do Sidekiq.
class PurgeLoginAttemptsJob < ApplicationJob
  queue_as :low_priority

  DEFAULT_RETENTION_DAYS = 90

  # Apaga em lotes para não segurar a tabela num único DELETE gigante na primeira
  # execução (a tabela nunca foi expurgada, então o primeiro corte pode ser grande).
  BATCH_SIZE = 5_000

  def perform(retention_days = nil)
    days = (retention_days || ENV.fetch('LOGIN_ATTEMPTS_RETENTION_DAYS', DEFAULT_RETENTION_DAYS)).to_i
    return Rails.logger.warn('[PurgeLoginAttemptsJob] retenção <= 0, expurgo abortado') if days <= 0

    cutoff = days.days.ago
    total = 0

    # `delete_all` não aceita `limit` no PostgreSQL; o lote sai por subconsulta de id.
    loop do
      batch_ids = LoginAttempt.where(created_at: ...cutoff).limit(BATCH_SIZE).select(:id)
      deleted = LoginAttempt.where(id: batch_ids).delete_all
      total += deleted
      break if deleted < BATCH_SIZE
    end

    Rails.logger.info("[PurgeLoginAttemptsJob] #{total} tentativas anteriores a #{cutoff.iso8601} removidas (retenção #{days}d)")
    total
  end
end
