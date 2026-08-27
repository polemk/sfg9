# frozen_string_literal: true

# S9 / BE-222, BE-223, BE-224 — **pagamentos**.
#
# ⚠ **DEC-53 (P-073): backend SIM, tela NÃO.** Os endpoints e este serviço são
# portados por inteiro; **nenhuma rota de UI** é criada, espelhando o legado, onde
# a aba PAGAMENTOS está comentada
# (`renegotiations/detail/_body.html.erb:22`). A decisão impõe uma condição que
# está cumprida aqui e no endpoint: **backend sem tela não pode ficar sem dono de
# autorização** — passa por `current_project!` e pela matriz igual a qualquer
# outro recurso. Foi exatamente assim que o P-022 (contratos sem gate) nasceu no
# legado. O QA do Phase 4 **não deve abrir defeito pela aba ausente**.
#
# Os pagamentos continuam alcançáveis pela tela **pela sublinha da parcela**
# (FE-227), que é como o legado realmente os expunha; o que não existe é a aba
# própria.
#
# **As três faces do D-52 morrem aqui:**
#
# 1. A parcela e a renegociação podiam divergir (dois ids soltos vindos do
#    `permit`). Agora o par é conferido no serviço **e** garantido por FK composta.
# 2. Não havia teto nenhum: o "pendente" era só rótulo do seletor na tela.
#    ⚠ Isto **muda o que hoje é aceito** e pode barrar lançamento que o operador
#    fazia — está registrado como tal na tarefa 2.24.
# 3. A mora podia ser negativa e reduzir o devido pelos dois lados.
#
# **Sem imputação automática:** o pagamento vai só para a parcela escolhida. O
# legado também não distribuía sobra entre parcelas, e inventar isso agora mudaria
# silenciosamente o destino do dinheiro.
class RenegotiationPaymentService < ProjectScopedService
  class << self
    def model = RenegotiationPayment
    def resource_label = 'Pagamento'

    def writable_attributes = %i[date installment_paid_value_with_interest_cm late_payment_value]

    def base_scope(project)
      model.for_project(project)
    end

    # **Ordem determinística** (BE-222). O legado não tinha `ORDER BY` nenhum: a
    # ordem dependia do plano do banco e mudava entre duas cargas da mesma tela.
    def index(project:, renegotiation:, installment: nil, params: {})
      scope = base_scope(project).where(renegotiation_id: renegotiation.id)
      scope = scope.where(renegotiation_installment_id: installment.id) if installment
      if params[:renegotiation_installment_id].present? && uuid?(params[:renegotiation_installment_id])
        scope = scope.where(renegotiation_installment_id: params[:renegotiation_installment_id])
      end
      { status: 200, data: scope.ordered }
    end

    def create_payment(installment:, attrs:, actor: nil)
      pagamento = RenegotiationPayment.new(
        renegotiation_installment: installment,
        renegotiation_id: installment.renegotiation_id,
        project_id: installment.project_id,
        **attrs.slice(*writable_attributes)
      )

      erro = over_pending(installment, pagamento)
      return { status: 422, error: erro } if erro

      salvar(pagamento) { Renegotiations::RecalculateInstallment.call!(installment) }
    end

    # **A edição NÃO pode mudar a parcela pela URL** (BE-222): `renegotiation_id`
    # e `renegotiation_installment_id` não estão em `writable_attributes`, então
    # não há caminho para o corpo movê-los.
    def update_payment(payment:, attrs:)
      installment = payment.renegotiation_installment
      payment.assign_attributes(attrs.slice(*writable_attributes))

      erro = over_pending(installment, payment)
      return { status: 422, error: erro } if erro

      salvar(payment) { Renegotiations::RecalculateInstallment.call!(installment) }
    end

    # **A exclusão REABRE a parcela** — `is_paid` é derivado de `pending_value`, e
    # o recálculo roda **uma vez** (o legado fazia `update` + `save` e disparava a
    # cascata em duplicidade).
    def destroy_payment(payment:)
      installment = payment.renegotiation_installment
      payment.destroy!
      Renegotiations::RecalculateInstallment.call!(installment)

      { status: 200, data: { deleted: true, id: payment.id.to_s } }
    end

    def find_in(renegotiation, id)
      return nil unless uuid?(id)

      RenegotiationPayment.find_by(id: id, renegotiation_id: renegotiation.id)
    end

    private

    # **Teto no pendente da parcela.** O pendente já lançado por OUTROS pagamentos
    # é descontado; na edição, o próprio pagamento sai da conta para que salvar
    # sem alterar o valor não seja recusado.
    #
    # A comparação usa `installment_paid_value_with_interest_cm`, **não** o total
    # com mora: a mora entra dos dois lados da conta da parcela (Q-B26) e
    # limitá-la aqui barraria o pagamento de juros por atraso, que é legítimo.
    def over_pending(installment, payment)
      return nil if installment.blank?

      outros = RenegotiationPayment
               .where(renegotiation_installment_id: installment.id)
               .where.not(id: payment.id)
               .sum(:installment_paid_value_with_interest_cm)

      devido = installment.main_value_with_interest_cm.to_d
      restante = devido - outros
      valor = payment.installment_paid_value_with_interest_cm.to_d
      return nil if valor <= restante

      "O valor pago não pode passar do pendente da parcela (#{formatar(restante)})."
    end

    def salvar(payment)
      RenegotiationPayment.transaction do
        payment.save!
        yield
      end
      { status: 200, data: payment.reload }
    rescue ActiveRecord::RecordInvalid => e
      { status: 422, error: e.record.errors.full_messages.to_sentence, details: e.record.errors.messages }
    end

    def formatar(valor)
      ActiveSupport::NumberHelper.number_to_currency(valor, unit: 'R$', separator: ',', delimiter: '.')
    end
  end
end
