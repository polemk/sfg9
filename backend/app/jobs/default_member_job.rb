# frozen_string_literal: true

# S0 / OPS-005, OPS-006 — insere o "membro padrão" em todos os projetos ativos.
#
# Duas coisas que o legado não tinha e que são o ponto desta tarefa:
#
#  1. **Enfileirado SÓ quando `is_default_member` muda.** No legado
#     (`user_decorator.rb:242-252`) o `create_memberships` era chamado em todo
#     `update` do usuário: trocar o telefone reenfileirava a varredura de todos
#     os projetos. O gatilho está em `User#enqueue_default_member_job`.
#  2. **Retry e falha VISÍVEL.** O `Delayed::Job` do legado falhava calado — o
#     projeto ficava com `job_state` em progresso para sempre. Aqui a falha
#     esgota o retry, é logada em `error` e é publicada no canal de progresso.
#
# Não usa `current_project!`: recebe os ids explicitamente. Job cruza projetos
# por definição — é uma das razões de o escopo NÃO ser `default_scope` (C1).
class DefaultMemberJob < ApplicationJob
  queue_as :low_priority

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?
    return unless user.is_default_member?

    created = 0
    Project.active.find_each do |project|
      membership = Membership.find_or_initialize_by(user_id: user.id, project_id: project.id)
      next unless membership.new_record?

      membership.role = 'participante'
      membership.save!
      created += 1
      # S13 / OPS-127 — a emissão passa pelo ponto único.
      #
      # **Regra de fronteira, num payload de websocket.** Este job publicava
      # `{ kind:, state: 'running' }` e o `useJobProgress.ts` lê `status`. O front
      # recebia o evento, não reconhecia estado nenhum e caía no ramo "running"
      # para sempre — inclusive quando o job FALHAVA, que é o caso em que o
      # usuário mais precisa saber. Os dois lados estavam certos sozinhos, e
      # nenhum portão pega isso: `rspec` verde, `tsc` limpo, barra mentindo.
      Sfg::JobProgress.publish(project_id: project.id, job_id: job_identifier(user),
                               status: 'running',
                               message: "Incluindo #{user.display_identifier} nos projetos")
    rescue ActiveRecord::RecordNotUnique
      # Corrida com outra execução: o índice único fez o trabalho, segue.
      next
    end

    Rails.logger.info("[DefaultMemberJob] #{user.display_identifier}: #{created} participações criadas")
    # Sem o evento de conclusão a barra fica em "running" para sempre na aba que
    # estava aberta — o job termina e a tela não sabe.
    Project.active.find_each do |project|
      Sfg::JobProgress.publish(project_id: project.id, job_id: job_identifier(user),
                               status: 'done', message: "#{created} participações criadas")
    end
    created
  end

  # Falha visível: quando o retry esgota, isto roda. Silêncio aqui é o defeito
  # que se está fechando.
  after_discard do |job, error|
    user_id = job.arguments.first
    Rails.logger.error("[DefaultMemberJob] FALHOU para user_id=#{user_id}: #{error.class}: #{error.message}")
    Project.active.find_each do |project|
      Sfg::JobProgress.publish(project_id: project.id,
                               job_id: "default_member:#{user_id}",
                               status: 'failed', error: error.message)
    end
  end

  def job_identifier(user) = "default_member:#{user.id}"
end
