# frozen_string_literal: true

# S11 / BE-114, BE-145, OPS-083, OPS-123 — **desativar um padrão de
# disponibilidade do projeto**, em segundo plano.
#
# **As guardas NÃO estão aqui, e isso é a correção do D-04/D-33.** No legado a
# regra "padrão obrigatório não desativa" morava em
# `ProjectAvailabilityTemplate#deactive_and_reorder!` — método que **nenhum
# caminho real chamava**: o controller enfileirava o job, e o job usava
# `background_deactivate`, que faz `template.is_active = 0` direto. A guarda
# existia e **nunca era executada**. Pior: a consulta de dependentes filtrava
# `project_id: self.id`, o **id do padrão** no lugar do id do projeto, então não
# achava dependente nenhum.
#
# Aqui a decisão de desativar é do `Availability::ProjectTemplateService`, que
# recusa **antes de enfileirar**. Este job só executa o que já foi autorizado —
# e um spec confere que desativar padrão obrigatório **não coloca job nenhum na
# fila**.
class DeactivateProjectTemplateJob < ApplicationJob
  queue_as :low_priority

  def self.job_identifier(template_id) = "availability_template_deactivate:#{template_id}"

  def perform(template_id, actor_id = nil)
    template = ProjectAvailabilityTemplate.find_by(id: template_id)
    return if template.nil?

    identificador = self.class.job_identifier(template.id)
    ator = actor_id.present? ? User.find_by(id: actor_id) : nil
    datas = template.entries.distinct.pluck(:date)

    Availability::TemplateLock.around(template, motivo: template.locked_message ||
                                      'Desativando o padrão e atualizando os lançamentos.',
                                      actor: ator, job_id: identificador) do
      ProjectAvailabilityTemplate.transaction do
        # Desce para os filhos, como o legado (`deactive!`). Não sobe: desativar
        # um filho não pode desligar o pai.
        ProjectAvailabilityTemplate.where(id: template.subtree_ids)
                                   .update_all(is_active: false, updated_at: Time.current)
      end

      recalcular_afetados(template, datas, identificador)
      Availability::TreeService.reorder_project!(template.project_id)
    end
  end

  private

  # OPS-123 — **pai sem lançamento na data conclui normalmente.**
  #
  # O legado fazia `recalculate_entry = parent_template.entries.where(...).first`
  # e, na linha seguinte, `entry_ids << recalculate_entry.id` **sem checar
  # nulo**: uma data em que o pai não tinha lançamento derrubava o job inteiro
  # com `NoMethodError` — e, pelo D-05, deixava o padrão bloqueado para sempre.
  # `compact` resolve, e o spec cobre exatamente esse caso.
  def recalcular_afetados(template, datas, identificador)
    return if datas.empty?

    alvos =
      if template.parent_template_id.present?
        AvailabilityEntry.where(availability_template_id: template.parent_template_id, date: datas)
      else
        base_ids = ProjectAvailabilityTemplate.for_project(template.project_id)
                                              .active.where(parent_template_id: nil).select(:id)
        AvailabilityEntry.where(availability_template_id: base_ids, date: datas)
      end

    total = alvos.count
    return if total.zero?

    alvos.find_each.with_index(1) do |entrada, indice|
      entrada.recompute_and_save!
      Availability::TemplateLock.step!(template, job_id: identificador, current: indice, total: total,
                                                 message: "Recalculando somatórios (#{indice}/#{total})")
    end
  end
end
