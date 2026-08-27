# frozen_string_literal: true

# S11 / OPS-081, OPS-120 — **semear um projeto com o catálogo global** de padrões
# de disponibilidade.
#
# Roda quando um projeto nasce. No legado era `Project#create_templates_from_global`,
# chamado por `InsertGlobalTemplateOnProjectsJob`, e tinha três problemas:
#
# 1. **Não era atômico.** Cada `ProjectAvailabilityTemplate.create` era
#    independente; uma falha no meio deixava o projeto com metade da árvore, sem
#    ninguém saber. E o `delegate` padrão só imprimia no stdout: **nenhuma tela
#    consumia o progresso**.
# 2. **Não era idempotente.** Rodar de novo duplicava a árvore inteira.
# 3. **Não copiava `is_adjusted`** (`project.rb:317-341`): todo padrão de
#    projeto nascia **não ajustado**, mesmo derivando de um global ajustado.
#    Copiar **muda número exibido** — está no `improvements-log.md`.
#
# `Availability::GlobalSeeder` resolve os três, e o mesmo código serve à
# propagação (OPS-121) — que é como as duas divergências de atributo do legado
# deixam de ser possíveis.
class SeedGlobalTemplatesJob < ApplicationJob
  queue_as :low_priority

  def self.job_identifier(project_id) = "availability_seed_global:#{project_id}"

  def perform(project_id, actor_id = nil)
    project = Project.find_by(id: project_id)
    return if project.nil?

    identificador = self.class.job_identifier(project.id)
    ator = actor_id.present? ? User.find_by(id: actor_id) : nil

    Sfg::JobProgress.publish(project_id: project.id, job_id: identificador, status: 'running',
                             percent: 0, message: 'Trazendo os padrões de disponibilidade do catálogo')

    begin
      resultado = Availability::GlobalSeeder.seed_project!(project, actor: ator, progress: lambda { |atual, total|
        Sfg::JobProgress.step(project_id: project.id, job_id: identificador, current: atual, total: total,
                              message: "Trazendo padrões (#{atual}/#{total})")
      })

      Sfg::JobProgress.publish(project_id: project.id, job_id: identificador, status: 'done',
                               message: "#{resultado[:created]} padrão(ões) trazido(s) do catálogo")
    rescue StandardError => e
      Sfg::JobProgress.publish(project_id: project.id, job_id: identificador, status: 'failed',
                               error: e.message)
      # `raise` sempre — ver `ApplicationJob`. Engolir a exceção não evita a
      # falha; evita que alguém fique sabendo dela (D-79).
      raise
    end
  end
end
