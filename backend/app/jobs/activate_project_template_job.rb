# frozen_string_literal: true

# S11 / BE-113, BE-144, OPS-082, OPS-122 — **ativar um padrão de disponibilidade
# do projeto**, em segundo plano.
#
# ## O `ensure` é a razão de este arquivo existir (D-05)
#
# No legado (`project_availability_template.rb:695-731`) o `template.unlocked!`
# era a **penúltima linha do caminho feliz**. Qualquer exceção antes dele — e o
# `Delayed::Job` engolia exceção, com `destroy_failed_jobs? false` e sem retry —
# deixava o padrão **bloqueado para sempre**, sem caminho de recuperação pela
# interface. `Availability::TemplateLock.around` põe o `unlock!` num `ensure`.
#
# ## OPS-122 — o logger global
#
# O legado fazia `ActiveRecord::Base.logger = nil` no início e restaurava o
# logger **dentro** do bloco protegido, na penúltima linha. Uma falha deixava o
# logger desligado **para o worker inteiro**, e todo job que rodasse depois
# naquele processo perdia o log de SQL. Aqui não se mexe no logger global: se o
# volume de SQL incomodar, o lugar é a configuração do ambiente, não uma
# atribuição a variável de classe no meio de um job.
class ActivateProjectTemplateJob < ApplicationJob
  queue_as :low_priority

  def self.job_identifier(template_id) = "availability_template_activate:#{template_id}"

  def perform(template_id, actor_id = nil)
    template = ProjectAvailabilityTemplate.find_by(id: template_id)
    return if template.nil?

    identificador = self.class.job_identifier(template.id)
    ator = actor_id.present? ? User.find_by(id: actor_id) : nil

    Availability::TemplateLock.around(template, motivo: template.locked_message ||
                                      'Ativando o padrão e atualizando os lançamentos.',
                                      actor: ator, job_id: identificador) do
      ProjectAvailabilityTemplate.transaction do
        # Ativar desce para a subárvore e sobe para os ancestrais — um padrão
        # ativo debaixo de um pai inativo não aparece na grade.
        ProjectAvailabilityTemplate.where(id: template.subtree_ids)
                                   .update_all(is_active: true, updated_at: Time.current)
        ancestor_ids(template).each_slice(50) do |ids|
          ProjectAvailabilityTemplate.where(id: ids).update_all(is_active: true, updated_at: Time.current)
        end
      end

      recalcular_lancamentos(template, identificador)
      Availability::TreeService.reorder_project!(template.project_id)
    end
  end

  private

  def ancestor_ids(template)
    ids = []
    atual = template.parent_template
    while atual
      ids << atual.id
      atual = atual.parent_template
    end
    ids
  end

  # Os lançamentos do próprio padrão e os do pai — os mesmos dois conjuntos que
  # `background_activate` recalculava, agora sem `AvailabilityEntry.find` dentro
  # de um laço sobre ids já carregados.
  def recalcular_lancamentos(template, identificador)
    alvos = [template.id, template.parent_template_id].compact
    lancamentos = AvailabilityEntry.where(availability_template_id: alvos).order(:date)
    total = lancamentos.count

    lancamentos.find_each.with_index(1) do |entrada, indice|
      entrada.recompute_and_save!
      Availability::TemplateLock.step!(template, job_id: identificador, current: indice, total: total,
                                                 message: "Atualizando lançamentos (#{indice}/#{total})")
    end
  end
end
