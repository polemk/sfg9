# frozen_string_literal: true

# S0 / DEC-59 #1 + DEC-78 #2 — retenção da trilha de auditoria, decidida NO
# INÍCIO, não depois de a tabela crescer.
#
# O payload é COMPLETO (DEC-78): cada versão guarda a foto inteira do registro.
# Payload completo com retenção infinita é como a base de auditoria fica maior
# que a base de produção. O mesmo raciocínio do DEC-60 (`login_attempts`, 90
# dias) vale aqui, com prazo maior porque é auditoria financeira e de acesso.
#
# `AUDIT_VERSIONS_RETENTION_DAYS` permite encurtar sem deploy. O padrão de 1825
# dias (5 anos) acompanha o prazo em que uma operação de crédito ainda pode ser
# questionada.
#
# **Agendamento:** este job precisa de uma linha no schedule versionado do
# `sidekiq-cron`. O arquivo de schedule é da fatia **S18** (`config/`), e por
# isso não é criado aqui — ver `upstream-flags.md` #13 (hoje o agendamento do
# `apl9` só existe no Redis, que é exatamente o que não se quer repetir).
class PurgeAuditVersionsJob < ApplicationJob
  queue_as :low_priority

  DEFAULT_RETENTION_DAYS = 1825

  def perform(retention_days = nil)
    days = (retention_days || ENV.fetch('AUDIT_VERSIONS_RETENTION_DAYS', DEFAULT_RETENTION_DAYS)).to_i
    return 0 if days <= 0

    cutoff = days.days.ago
    deleted = PaperTrail::Version.where(created_at: ...cutoff).delete_all
    Rails.logger.info("[PurgeAuditVersionsJob] #{deleted} versões anteriores a #{cutoff.to_date} removidas")
    deleted
  end
end
