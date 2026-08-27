# frozen_string_literal: true

# DEC-90 — expurgo de `email_logs` com retenção de 180 dias.
#
# O log de e-mail guarda **só metadados** (remetente, destinatário, assunto, status,
# timestamp) — sem corpo. No legado `livetat_mailer_contacts` guarda `message`, e a
# coluna foi promovida de `string` para `text` justamente para caber o corpo; como os
# e-mails vivos são de identidade, o corpo carrega o próprio código de acesso. Guardar
# o corpo seria guardar a credencial em texto puro, com retenção infinita.
#
# TOLERÂNCIA DELIBERADA: a tabela `email_logs` é criada por outra fatia. Enquanto ela
# não existir o job registra e sai sem erro — assim o agendamento pode nascer junto com
# o do DEC-60 (mesmo mecanismo, uma tarefa só) sem que o portão de boot reprove nem o
# cron entre em retry eterno. Quando a migration chegar, o job passa a expurgar sozinho.
class PurgeEmailLogsJob < ApplicationJob
  queue_as :low_priority

  DEFAULT_RETENTION_DAYS = 180
  BATCH_SIZE = 5_000

  def perform(retention_days = nil)
    unless table_ready?
      Rails.logger.info('[PurgeEmailLogsJob] tabela email_logs ainda não existe; nada a expurgar')
      return 0
    end

    days = (retention_days || ENV.fetch('EMAIL_LOGS_RETENTION_DAYS', DEFAULT_RETENTION_DAYS)).to_i
    return Rails.logger.warn('[PurgeEmailLogsJob] retenção <= 0, expurgo abortado') if days <= 0

    cutoff = days.days.ago
    model = email_log_model
    total = 0

    loop do
      batch_ids = model.where(created_at: ...cutoff).limit(BATCH_SIZE).select(:id)
      deleted = model.where(id: batch_ids).delete_all
      total += deleted
      break if deleted < BATCH_SIZE
    end

    Rails.logger.info("[PurgeEmailLogsJob] #{total} registros anteriores a #{cutoff.iso8601} removidos (retenção #{days}d)")
    total
  end

  private

  def table_ready?
    ActiveRecord::Base.connection.table_exists?('email_logs')
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    false
  end

  # Usa o model quando ele existir; senão fala com a tabela direto. Evita acoplar
  # esta fatia à fatia que cria o `EmailLog`.
  def email_log_model
    return EmailLog if Object.const_defined?(:EmailLog)

    @email_log_model ||= Class.new(ActiveRecord::Base) { self.table_name = 'email_logs' }
  end
end
