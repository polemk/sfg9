# frozen_string_literal: true

module Api
  module V1
    # S9 / BE-222, BE-223, BE-224 — **pagamentos**.
    #
    # ⚠ **DEC-53 (P-073) — backend SIM, tela NÃO.** O usuário decidiu: *"trazer o
    # backend do pagamentos mas continua desabilitado como no legado ou seja sem
    # view por enquanto"*. No legado a aba PAGAMENTOS está comentada
    # (`renegotiations/detail/_body.html.erb:22`), e no ai9 ela também não existe.
    #
    # **A condição que a decisão impõe está cumprida aqui:** backend sem tela
    # **não pode ficar sem dono de autorização**. Estas rotas são alcançáveis por
    # URL, e por isso passam por `authenticate_user!`, por `authorize!` contra a
    # matriz e por `current_project!` — exatamente como qualquer outro recurso.
    # Foi pulando esse passo que o P-022 (contratos sem gate) nasceu no legado.
    #
    # **O QA do Phase 4 não deve abrir defeito pela aba ausente**: é escolha, e
    # está escrita. Os pagamentos continuam visíveis e editáveis pela sublinha da
    # parcela (FE-227) — que é como o legado realmente os expunha.
    class RenegotiationPayments < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'renegotiation_payments'

      namespace 'renegotiations/:renegotiation_id/payments' do
        before { authenticate_user! }

        desc 'Lista os pagamentos de uma renegociação' do
          detail 'ORDEM DETERMINÍSTICA (BE-222): o legado não tinha `ORDER BY` nenhum e a ordem dependia ' \
                 'do plano do banco. Paginação real (D-20).'
          success [code: 200, model: Api::Entities::RenegotiationPayment]
          is_array true
        end
        params do
          requires :renegotiation_id, type: String
          optional :renegotiation_installment_id, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 50
        end
        get '' do
          authorize!(RESOURCE, :read)
          renegotiation = fetch_renegotiation!

          scope = RenegotiationPaymentService.index(
            project: current_project!, renegotiation: renegotiation, params: params
          )[:data]

          Api::Entities::RenegotiationPayment.represent(paginate(scope).to_a)
        end

        desc 'Lança um pagamento contra UMA parcela' do
          detail 'Teto no pendente da parcela; mora negativa recusada; parcela de outra renegociação ' \
                 'recusada (as três faces do D-52). SEM imputação automática: o pagamento vai só para a ' \
                 'parcela escolhida.'
        end
        params do
          requires :renegotiation_id, type: String
          requires :renegotiation_installment_id, type: String
          requires :installment_paid_value_with_interest_cm, type: BigDecimal
          # **A data é EDITÁVEL** (D-B12). No legado o campo era travado em "hoje",
          # o que tornava `days_late` sempre 0 e impedia lançamento retroativo.
          requires :date, type: Date
          optional :late_payment_value, type: BigDecimal, default: 0
        end
        post '' do
          authorize!(RESOURCE, :create)
          parcela = fetch_installment!(params[:renegotiation_installment_id])

          attrs = declared(params, include_missing: false).symbolize_keys
          resultado = RenegotiationPaymentService.create_payment(
            installment: parcela, attrs: attrs, actor: acting_user
          )
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] >= 400

          status 201
          Api::Entities::RenegotiationPayment.represent(resultado[:data])
        end

        desc 'Atualiza um pagamento' do
          detail 'A edição **não** pode mudar a parcela pela URL (BE-222): `renegotiation_installment_id` ' \
                 'não é gravável. Recalcula UMA vez — o legado fazia `update` + `save` e disparava a ' \
                 'cascata em duplicidade.'
        end
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
          optional :installment_paid_value_with_interest_cm, type: BigDecimal
          optional :date, type: Date
          optional :late_payment_value, type: BigDecimal
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          pagamento = fetch_payment!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id, :renegotiation_id)
          resultado = RenegotiationPaymentService.update_payment(payment: pagamento, attrs: attrs)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::RenegotiationPayment.represent(resultado[:data])
        end

        desc 'Remove um pagamento — a parcela REABRE'
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
        end
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          pagamento = fetch_payment!

          resultado = RenegotiationPaymentService.destroy_payment(payment: pagamento)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end

      helpers do
        def fetch_renegotiation!
          resultado = RenegotiationService.show(project: current_project!, id: params[:renegotiation_id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end

        def fetch_installment!(id)
          parcela = RenegotiationInstallmentService.find_in(fetch_renegotiation!, id)
          error!({ error: 'not_found', message: 'Parcela não encontrada.' }, 404) if parcela.nil?
          parcela
        end

        def fetch_payment!
          pagamento = RenegotiationPaymentService.find_in(fetch_renegotiation!, params[:id])
          error!({ error: 'not_found', message: 'Pagamento não encontrado.' }, 404) if pagamento.nil?
          pagamento
        end
      end
    end
  end
end
