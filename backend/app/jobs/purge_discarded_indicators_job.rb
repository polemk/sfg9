# frozen_string_literal: true

# S10 / OPS-313 — **purga dos indicadores descartados**.
#
# A exclusão de indicador virou lógica (`indicators.discarded_at`, D-66): o
# registro sai das listas e **os lançamentos ficam**. Este job é a segunda
# metade — o que finalmente apaga a linha, muito depois, quando ela já não pode
# machucar ninguém.
#
# ## As duas condições, e por que elas não são negociáveis
#
# 1. **Sem lançamento.** Apagar de verdade um indicador que ainda tem entries
#    seria reintroduzir o D-66 por um caminho mais lento: a série histórica
#    sumiria junto, só que num job noturno em vez de num clique. Se ainda há
#    histórico, o indicador **fica descartado para sempre** — e isso é o
#    comportamento certo, não uma falha do expurgo.
# 2. **Sem conexão de projeto.** Mesmo motivo, e a FK `NO ACTION` de
#    `project_indicator_connections` recusaria de qualquer forma.
#
# O prazo é longo (`INDICATORS_RETENTION_DAYS`, 365 dias por padrão) porque a
# única razão de apagar é higiene, e o custo de errar é perda de cadastro.
#
# A trilha de quem descartou está no `paper_trail` do próprio `Indicator`
# (`Sfg::AuditTrail::VERSIONED`), e o `destroy` daqui também gera versão — então
# depois do expurgo ainda se sabe o que existia.
#
# Agendado em `config/schedule.yml`, nunca pela Web UI do Sidekiq.
class PurgeDiscardedIndicatorsJob < ApplicationJob
  queue_as :low_priority

  DEFAULT_RETENTION_DAYS = 365

  def perform(retention_days = nil)
    days = (retention_days || ENV.fetch('INDICATORS_RETENTION_DAYS', DEFAULT_RETENTION_DAYS)).to_i
    return Rails.logger.warn('[PurgeDiscardedIndicatorsJob] retenção <= 0, expurgo abortado') if days <= 0

    cutoff = days.days.ago
    apagados = 0
    mantidos = 0

    Indicator.discarded.where(discarded_at: ...cutoff).find_each do |indicator|
      entries = indicator.entries.count
      conexoes = indicator.project_indicator_connections.count

      if entries.positive? || conexoes.positive?
        mantidos += 1
        Rails.logger.info(
          "[PurgeDiscardedIndicatorsJob] indicador #{indicator.id} (#{indicator.title}) MANTIDO: " \
          "#{entries} lançamento(s) e #{conexoes} conexão(ões). Apagar levaria a série histórica junto (D-66)."
        )
        next
      end

      indicator.destroy!
      apagados += 1
    end

    Rails.logger.info(
      "[PurgeDiscardedIndicatorsJob] #{apagados} indicador(es) descartado(s) antes de #{cutoff.iso8601} " \
      "removido(s); #{mantidos} mantido(s) por terem vínculo (retenção #{days}d)"
    )
    apagados
  end
end
