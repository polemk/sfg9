# frozen_string_literal: true

# S13 / OPS-466 — **o filho** da propagação de padrão global (D-80).
#
# Um job por projeto. Nasceu para que a promessa que o coordenador já fazia por
# escrito passasse a ser verdade no código: *"um projeto que falha não derruba os
# outros"*.
#
# ## O defeito que este arquivo fecha, e ele estava VIVO
#
# Até 26/08/2026 a propagação era **um job só** com o laço dentro
# (`PropagateGlobalTemplateJob#inserir_nos_projetos`). O `rescue` do bloco
# publicava a falha daquele projeto e terminava em `raise` — que é a regra certa
# de `ApplicationJob` — mas, num laço, o `raise` **aborta o `find_each`**. O
# comentário ao lado dizia "e o job segue"; ele não seguia. Com N projetos, o
# primeiro que falhasse deixava os N-1 seguintes sem o padrão, e a retentativa do
# Sidekiq recomeçava do zero — reprocessando os que já tinham dado certo (é
# idempotente, então não duplicava, mas o tempo dobrava a cada tentativa).
#
# Além disso, a request pagava por **N projetos** dentro de uma execução só: a
# fila ficava ocupada com um job longo em vez de N curtos, e o painel do Sidekiq
# mostrava "1 job" para um trabalho que podia levar minutos.
#
# ## O contrato do payload NÃO mudou
#
# O `job_id` continua sendo `availability_propagate_global:<id do global>`, o
# mesmo que a tela já consome pelo `useJobProgress`. **Regra de fronteira:**
# quebrar a propagação em N jobs é mudança de execução, não de protocolo — quem
# ouve o `ProjectProgressChannel` não precisa saber que agora há mais de um
# processo do outro lado.
#
# **UM evento por projeto, exatamente um.** Publicar `running` e depois `done`
# para uma inserção instantânea faz a tela invalidar a consulta duas vezes — o
# mesmo modo de falha do `WhatsappInstanceChannel`, que assinava duas chaves e
# entregava todo evento em dobro.
class PropagateGlobalTemplateToProjectJob < ApplicationJob
  queue_as :low_priority

  def perform(global_template_id, project_id, actor_id = nil)
    global = GlobalAvailabilityTemplate.find_by(id: global_template_id)
    project = Project.find_by(id: project_id)
    # Global ou projeto removido entre o despacho e a execução: não é falha, e
    # o coordenador precisa saber que este filho terminou — senão o relatório
    # dele nunca fecha.
    if global.nil? || project.nil?
      PropagateGlobalTemplateJob.register_outcome!(global_template_id, project_id, 'skipped')
      return
    end

    identificador = PropagateGlobalTemplateJob.job_identifier(global.id)
    ator = actor_id.present? ? User.find_by(id: actor_id) : nil

    begin
      Availability::GlobalSeeder.insert_into_project!(project, global, actor: ator)
    rescue StandardError => e
      Rails.logger.error("[PropagateGlobalTemplateToProjectJob] projeto #{project.id}: #{e.class}: #{e.message}")
      Sfg::JobProgress.publish(project_id: project.id, job_id: identificador,
                               status: 'failed', error: e.message)
      # O desfecho é gravado **antes** de relançar, e não só no `after_discard`:
      # assim o relatório do coordenador mostra a falha na hora, e não depois de
      # 25 retentativas. Como o registro é por projeto e idempotente, uma
      # retentativa que dê certo troca o `failed` por `completed`.
      PropagateGlobalTemplateJob.register_outcome!(global.id, project.id, 'failed')
      # `raise` sempre (contrato D-C): o Sidekiq retenta **este** projeto, e só
      # ele. Os irmãos já estão na fila e não são afetados.
      raise
    end

    Sfg::JobProgress.publish(project_id: project.id, job_id: identificador, status: 'done',
                             message: "\"#{global.title}\" disponível neste projeto")
    PropagateGlobalTemplateJob.register_outcome!(global.id, project.id, 'completed')
  end

  # Rede de segurança para a falha que não passa pelo `rescue` acima — o global
  # ou o projeto sumindo no meio, por exemplo.
  #
  # **Cuidado medido:** este bloco roda a **cada tentativa**, não só na última.
  # O ActiveJob considera descarte toda exceção que ele próprio não trata, e a
  # retentativa do Sidekiq é opaca para ele. Foi assim que o relatório fechou
  # `completed: 2, failed: 2` para três projetos na primeira execução real. Por
  # isso o registro é **por projeto e idempotente** — repetir não soma.
  after_discard do |job, error|
    global_template_id, project_id = job.arguments
    Rails.logger.error("[PropagateGlobalTemplateToProjectJob] DESISTIU global=#{global_template_id} " \
                       "projeto=#{project_id}: #{error.class}: #{error.message}")
    PropagateGlobalTemplateJob.register_outcome!(global_template_id, project_id, 'failed')
  end
end
