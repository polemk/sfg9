# frozen_string_literal: true

# S4 / OPS-080 — **os membros padrão entram no projeto recém-criado**.
#
# É o espelho do `DefaultMemberJob` (S0): lá o gatilho é o usuário virar membro
# padrão e a varredura é de projetos; aqui o gatilho é o projeto nascer e a
# varredura é de usuários. Os dois existem porque os dois eventos existem.
#
# **Não chama `current_project!`** — recebe `project_id` como argumento
# explícito. Job cruza projetos por definição, e é uma das razões de o escopo
# não ser `default_scope` (contrato C1, regra 5).
#
# Fecha o **D-05**: no legado `destroy_failed_jobs? false` e o job falho sumia
# da fila sem deixar rastro; o projeto ficava com `job_state` "em progresso"
# para sempre. Aqui o Sidekiq faz retry, a falha é logada em `error` e é
# **publicada no canal de progresso** — a barra da tela chega em "failed" em vez
# de girar sozinha.
class LinkDefaultMembersJob < ApplicationJob
  queue_as :low_priority

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  # BE-088 — identificador PRÓPRIO. No legado as duas tarefas da criação
  # escreviam no mesmo `job_id` e se atropelavam.
  def self.job_identifier(project_id) = "link_default_members:#{project_id}"

  def perform(project_id)
    project = Project.find_by(id: project_id)
    return if project.nil?

    identifier = self.class.job_identifier(project.id)
    padroes = User.where(is_default_member: true)
    total = padroes.count

    Sfg::JobProgress.publish(project_id: project.id, job_id: identifier, status: 'running',
                             percent: 0, message: 'Vinculando membros padrão')

    criadas = 0
    padroes.find_each.with_index(1) do |user, indice|
      membership = Membership.find_or_initialize_by(user_id: user.id, project_id: project.id)
      if membership.new_record?
        membership.role = 'participante'
        membership.save!
        criadas += 1
      end

      Sfg::JobProgress.publish(project_id: project.id, job_id: identifier, status: 'running',
                               percent: (indice * 100 / [total, 1].max),
                               message: "Vinculando membros padrão (#{indice}/#{total})")
    rescue ActiveRecord::RecordNotUnique
      # Corrida com o `DefaultMemberJob` rodando pelo outro lado: o índice único
      # fez o trabalho. **O `rescue` do legado era vazio** (OPS-085) e engolia
      # qualquer erro, não só este.
      next
    end

    Rails.logger.info("[LinkDefaultMembersJob] projeto #{project.id}: #{criadas} participações criadas")
    Sfg::JobProgress.publish(project_id: project.id, job_id: identifier, status: 'done',
                             percent: 100, message: "#{criadas} participações criadas")
    criadas
  end

  after_discard do |job, error|
    project_id = job.arguments.first
    Rails.logger.error("[LinkDefaultMembersJob] FALHOU para project_id=#{project_id}: " \
                       "#{error.class}: #{error.message}")
    Sfg::JobProgress.publish(project_id: project_id, job_id: job_identifier(project_id),
                             status: 'failed', error: error.message)
  end
end
