# frozen_string_literal: true

# S11 / BE-115, BE-146, OPS-084, OPS-124, DC-20 — **remover um padrão de
# disponibilidade do projeto**, em segundo plano.
#
# ## O defeito mais caro do módulo
#
# `ProjectAvailabilityTemplate#background_remove_templates` do legado fazia,
# nesta ordem: desce recursivamente pelos filhos, **`self.entries.destroy_all`**
# e devolve os ids para o chamador destruir. O `has_many :entries` declarava
# `dependent: :restrict_with_error` — e o `destroy_all` explícito **contornava a
# própria restrição**. Resultado: remover um padrão apagava, sem transação e sem
# aviso, todos os lançamentos financeiros dele e da subárvore.
#
# **DC-20:** o servidor **recusa 422** a remoção de padrão com lançamentos, e a
# recusa acontece no `Availability::ProjectTemplateService`, antes de este job
# existir. Este job só remove o que já foi verificado como removível — e ainda
# assim confere de novo, porque entre a recusa e a execução pode ter entrado
# lançamento.
#
# **OPS-124:** nada permanece em falha (uma transação), reexecutar depois de
# concluído termina **sem erro**, e nenhum estado é gravado sobre registro já
# destruído.
class RemoveProjectTemplateJob < ApplicationJob
  queue_as :low_priority

  class HasEntries < StandardError; end

  def self.job_identifier(template_id) = "availability_template_remove:#{template_id}"

  def perform(template_id, actor_id = nil)
    template = ProjectAvailabilityTemplate.find_by(id: template_id)
    # **Reexecução depois de concluída termina sem erro** (OPS-124). O registro
    # já não existe: não há o que remover, e isso não é falha.
    if template.nil?
      Rails.logger.info("[RemoveProjectTemplateJob] padrão #{template_id} já removido — nada a fazer")
      return
    end

    identificador = self.class.job_identifier(template.id)
    ator = actor_id.present? ? User.find_by(id: actor_id) : nil
    project_id = template.project_id
    pai_id = template.parent_template_id
    ids = template.subtree_ids

    Availability::TemplateLock.around(template, motivo: template.locked_message ||
                                      'Removendo o padrão.', actor: ator, job_id: identificador) do
      # A conferência do DC-20, de novo e no último instante possível.
      if AvailabilityEntry.where(availability_template_id: ids).exists?
        raise HasEntries, 'O padrão passou a ter lançamentos entre o pedido e a execução; nada foi removido.'
      end

      ProjectAvailabilityTemplate.transaction do
        # Do mais fundo para a raiz, para que o `restrict_with_error` do pai não
        # dispare. `destroy!`, nunca `destroy_all`: exclusão parcial em silêncio
        # é como o legado apagava lançamento sem ninguém perceber.
        ProjectAvailabilityTemplate.where(id: ids).order(level: :desc).each(&:destroy!)
      end

      recalcular_afetados(project_id, pai_id)
      Availability::TreeService.reorder_project!(project_id)
    end
  end

  private

  # O pai perdeu um filho: o somatório dele muda. Sem pai, os padrões base do
  # projeto são os que mudam (o saldo acumulado deles somava a subárvore).
  def recalcular_afetados(project_id, pai_id)
    alvos =
      if pai_id.present?
        AvailabilityEntry.where(availability_template_id: pai_id)
      else
        base_ids = ProjectAvailabilityTemplate.for_project(project_id)
                                              .active.where(parent_template_id: nil).select(:id)
        AvailabilityEntry.where(availability_template_id: base_ids)
      end

    alvos.find_each(&:recompute_and_save!)
  end
end
