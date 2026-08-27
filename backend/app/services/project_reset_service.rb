# frozen_string_literal: true

# S4 / BE-092 — **limpar o projeto de treinamento**.
#
# O projeto de treinamento (`is_sandbox`) existe para o cliente errar à vontade.
# Ele **nunca é removido** — a rota de exclusão o limpa e o devolve ao estado
# inicial. A regra está em dois lugares, de propósito: no `before_destroy` do
# model (que barra qualquer caminho, inclusive console e job) e aqui.
#
# Três coisas que mudam em relação ao `Project#wipe_data` do legado:
#
# 1. **O segmento não é um id fixo.** O legado fazia `self.segment_id = 1`
#    (**D-26**): o "1" era o primeiro segmento cadastrado em 2021, e apagar
#    aquele registro deixaria a limpeza apontando para nada. Aqui o segmento é
#    resolvido pela **chave de integração** — dado, editável pelo cliente, e com
#    ausência tratada (o segmento é opcional).
# 2. **É uma transação.** No legado eram 17 `destroy_all` soltos: falhar no
#    décimo deixava o projeto pela metade, sem nada dizer.
# 3. **`Renegotiation` não é apagada duas vezes.** O legado chamava
#    `Renegotiation.where(...).destroy_all` e, no bloco, iterava sobre objetos
#    **já destruídos** para apagar as parcelas — e depois chamava `destroy_all`
#    de novo. As parcelas ficavam.
#
# **O que é PRESERVADO** é o mesmo do legado, e é o que faz o projeto continuar
# sendo o mesmo projeto: `name`, `slug`, `user_id`, `color`, `has_bi`,
# `legacy_id` e `integration_key`.
class ProjectResetService
  class << self
    include ApiResponseHandler

    # Chave do segmento aplicado ao projeto de treinamento depois da limpeza.
    # É **dado**, não id: o cliente cadastra o segmento e a limpeza o encontra.
    SANDBOX_SEGMENT_KEY = 'treinamento'

    # A ordem importa: das folhas para a raiz, contornando os bloqueios de
    # exclusão. Declarada por NOME porque metade das tabelas nasce em S5..S11 —
    # a que ainda não existe é simplesmente pulada, e a linha continua escrita.
    WIPE_ORDER = [
      %w[RiskMovement project_id],
      %w[RiskEntry project_id],
      %w[RiskOperationExtension project_id],
      %w[RiskOperation project_id],
      %w[StructuredOperation project_id],
      %w[RenegotiationPayment project_id],
      %w[RenegotiationInstallment project_id],
      %w[Renegotiation project_id],
      %w[ReceivableTax project_id],
      %w[ReceivableEntry project_id],
      %w[IndicatorEntry project_id],
      %w[AvailabilityEntry project_id],
      %w[ProjectAvailabilityTemplate project_id],
      %w[RiskControl project_id],
      %w[ProjectGuarantee project_id],
      %w[Provider project_id],
      %w[Company project_id],
      %w[ProjectToCarrierConnection project_id],
      %w[ProjectIndicatorConnection project_id]
    ].freeze

    def call(project:, actor: nil)
      return validation_error_response('Só o projeto de treinamento é limpo.') unless project.is_sandbox?

      apagados = {}

      Project.transaction do
        WIPE_ORDER.each do |class_name, foreign_key|
          klass = BlockingDependents.dependent_class_with_column(class_name, foreign_key)
          next if klass.nil?

          total = klass.where(foreign_key => project.id).count
          next if total.zero?

          # `destroy_all`, não `delete_all`: os callbacks precisam rodar (é o que
          # apaga o anexo do ActiveStorage junto, por exemplo).
          klass.where(foreign_key => project.id).destroy_all
          apagados[class_name] = total
        end

        reset_attributes!(project)
        reset_memberships!(project)
        Company.create!(project: project, title: 'Empresa Padrão')
      end

      LinkDefaultMembersJob.perform_later(project.id)
      # S13 / OPS-465 — o `WIPE_ORDER` acima apaga os padrões de disponibilidade
      # junto com o resto. Sem esta linha o projeto de treinamento voltaria da
      # limpeza **sem painel nenhum**. O legado fazia o mesmo no seu caminho de
      # recriação (`../sfg/app/models/project.rb:738`).
      SeedGlobalTemplatesJob.perform_later(project.id, actor&.id)

      Rails.logger.info(
        "[ProjectResetService] projeto #{project.slug} limpo por #{actor&.id.inspect}: #{apagados.inspect}"
      )

      { status: 200, data: { reset: true, id: project.id, deleted: apagados } }
    rescue ActiveRecord::RecordInvalid => e
      error_response(e.record.errors.full_messages.to_sentence, 422)
    end

    private

    def reset_attributes!(project)
      project.assign_attributes(
        segment: sandbox_segment,
        sub_segment_id: nil,
        is_active: true,
        has_safegold_management: true,
        address_type: nil, address: nil, address_number: nil, address_complement: nil,
        neighborhood: nil, cep: nil, address_state: nil, address_city: nil,
        closing_date: nil, importing_id: nil,
        responsible_id: nil, responsible_name: nil, responsible_email: nil,
        job_state: nil, job_progress: nil, job_report: nil
      )
      project.availability_note.destroy if project.rich_text_availability_note.present?
      project.save!
    end

    # D-26 — por CHAVE, nunca por id fixo. `nil` é resposta válida: o segmento é
    # opcional, e é melhor um projeto sem segmento do que um apontando para o
    # primeiro registro que sobrou na tabela.
    def sandbox_segment
      Segment.find_by(integration_key: SANDBOX_SEGMENT_KEY)
    end

    def reset_memberships!(project)
      Membership.for_project(project).destroy_all
      Membership.create!(project: project, user_id: project.user_id, role: 'responsavel')
    end
  end
end
