# frozen_string_literal: true

# S9 / BE-213, BE-214, BE-215, BE-216, BE-217, BE-221 — **parcelas (previsões)**.
#
# O escopo é a **renegociação**, que por sua vez já veio de `current_project!`.
# Uma parcela de outra renegociação — mesmo do mesmo projeto — não é encontrada,
# e uma parcela de outro projeto responde o **mesmo 404** de uma inexistente.
class RenegotiationInstallmentService < ProjectScopedService
  class << self
    def model = RenegotiationInstallment
    def resource_label = 'Parcela'
    def resource_genero = :feminino

    # Só os três valores digitados e a data. `renegotiation_id`, `project_id`,
    # `batch_token`, `color`, `number` e os **oito derivados** vêm do servidor.
    def writable_attributes = %i[due_date main_value interest_value monetary_correction_value]

    def base_scope(project)
      model.for_project(project).includes(:payments)
    end

    # Lista as parcelas de UMA renegociação, ordenadas por vencimento, com os
    # pagamentos. **A paginação funciona** — no legado `l` e `o` eram lidos do
    # parâmetro, guardados em variáveis de instância e **nunca aplicados** à
    # relação (D-20); a listagem devolvia tudo.
    def index(project:, renegotiation:, params: {})
      scope = base_scope(project).where(renegotiation_id: renegotiation.id).ordered
      scope = scope.where(is_paid: truthy?(params[:is_paid])) unless params[:is_paid].nil?
      { status: 200, data: scope }
    end

    # Cria uma parcela ou um lote. A regra inteira mora em
    # `Renegotiations::CreateInstallmentsBatch`, que é chamado **também** pela
    # prévia da tela — é o contrato C2.
    def create_batch(renegotiation:, attrs:)
      Renegotiations::CreateInstallmentsBatch.call(renegotiation: renegotiation, attrs: attrs)
    end

    # **A edição recalcula e renumera** (BE-221). Duas consequências que o legado
    # já tinha e que ficam preservadas:
    #  - mudar o vencimento pode mudar a POSIÇÃO da parcela, e a renumeração
    #    reordena todas;
    #  - **aumentar o valor REABRE parcela quitada**, porque `is_paid` é derivado
    #    de `pending_value <= 0` e nada mais.
    def update_installment(installment:, attrs:)
      writable = attrs.slice(*writable_attributes)

      # `renegotiation_id` e `project_id` **não estão** em `writable_attributes`:
      # não há caminho pelo qual uma edição mova a parcela de renegociação ou de
      # tenant pela URL. É a metade que o legado esquecia — lá o `permit` aceitava
      # `renegotiation_id` do corpo e o `update` não o sobrescrevia.
      RenegotiationInstallment.transaction do
        installment.assign_attributes(writable)
        installment.save!
      end

      Renegotiations::RecalculateInstallment.call!(installment, renumber: false, broadcast: false)
      Renegotiations::RenumberInstallments.call(installment.renegotiation)
      Renegotiations::AggregateService.recalculate!(installment.renegotiation)

      { status: 200, data: installment.reload }
    rescue ActiveRecord::RecordInvalid => e
      { status: 422, error: e.record.errors.full_messages.to_sentence, details: e.record.errors.messages }
    rescue ActiveRecord::RecordNotUnique
      { status: 422, error: 'Já existe parcela com este vencimento nesta renegociação.' }
    end

    # **Exclusão barrada por pagamento**, com o motivo. No legado o `destroy`
    # esbarrava no `restrict_with_error` da associação e o controller respondia
    # `unprocessable_entity` **sem corpo** — a tela não dizia por quê.
    def destroy_installment(installment:)
      if installment.payment?
        return { status: 422,
                 error: 'Não é possível remover: esta parcela tem pagamento lançado. ' \
                        'Remova o pagamento antes.' }
      end

      renegotiation = installment.renegotiation

      RenegotiationInstallment.transaction do
        installment.destroy!
        Renegotiations::RenumberInstallments.call(renegotiation)
        Renegotiations::AggregateService.recalculate!(renegotiation, broadcast: false)
      end

      RenegotiationChannel.publish_changed(renegotiation)
      { status: 200, data: { deleted: true, id: installment.id.to_s } }
    end

    # Localiza uma parcela DENTRO da renegociação. É a forma canônica do C1
    # aplicada ao segundo nível: o par (renegociação, parcela) tem de fechar.
    def find_in(renegotiation, id)
      return nil unless uuid?(id)

      RenegotiationInstallment.find_by(id: id, renegotiation_id: renegotiation.id)
    end
  end
end
