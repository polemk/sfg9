# frozen_string_literal: true

# Entidade que carrega o estado do próprio job — OPS-463 / DB-460.
#
#     class Project < ApplicationRecord
#       include JobProgressable
#     end
#
# Exige as colunas `job_state` (string) e `job_progress` (integer). **Não existe
# tabela de fila**: o legado guardava o progresso na linha de `delayed_jobs` e
# `projects.job_id` era FK para ela; o Sidekiq não tem registro relacional, então
# esse acoplamento não podia sobreviver (DB-460, decisão D2).
#
# Consequência que o runbook de S14 precisa saber e que está escrita aqui porque é
# aqui que ela se torna verdade: **job pendente no cutover não é importado**. O que
# estiver em voo no legado é reexecutado ou descartado explicitamente.
module JobProgressable
  extend ActiveSupport::Concern

  included do
    scope :with_ongoing_job, -> { where(job_state: 'running') }
  end

  class_methods do
    # Marcador de leitura para `Sfg::JobProgress.persist` e para a conferência de
    # contrato — evita `respond_to?(:job_state)`, que dá `true` para qualquer coisa.
    def job_progressable? = true
  end

  def ongoing_job? = job_state.to_s == 'running'

  def failed_job? = job_state.to_s == 'failed'

  # Percentual para a tela.
  #
  # **Dois defeitos do legado corrigidos aqui**, e os dois faziam a barra mentir:
  #  1. sem job, `live_progress_percent` devolvia **100** — uma entidade que nunca
  #     rodou nada aparecia como "concluída";
  #  2. no fim do processamento devolvia **0**, porque o registro do job já tinha
  #     sido apagado da fila e o cálculo caía no ramo do nil.
  #
  # Aqui: `nil` quando não há job (a tela não desenha barra nenhuma), o número real
  # enquanto roda, e 100 só quando terminou de verdade.
  def live_progress_percent
    case job_state.to_s
    when 'running' then job_progress.to_i.clamp(0, 100)
    when 'done' then 100
    else nil
    end
  end

  # Marca o início. Zera o progresso — senão a barra começa no valor da rodada
  # anterior e anda para trás.
  def start_job!(job_id: nil, project_id: nil, message: nil)
    Sfg::JobProgress.publish(project_id: project_id || try(:project_id) || try(:id),
                             job_id: job_id || self.class.name,
                             status: 'running', record: self, percent: 0, message: message)
  end

  def finish_job!(job_id: nil, project_id: nil, message: nil)
    Sfg::JobProgress.publish(project_id: project_id || try(:project_id) || try(:id),
                             job_id: job_id || self.class.name,
                             status: 'done', record: self, message: message)
  end

  def fail_job!(error, job_id: nil, project_id: nil)
    Sfg::JobProgress.publish(project_id: project_id || try(:project_id) || try(:id),
                             job_id: job_id || self.class.name,
                             status: 'failed', record: self,
                             error: error.respond_to?(:message) ? error.message : error.to_s)
  end
end
