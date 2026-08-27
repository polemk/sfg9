# frozen_string_literal: true

module Api
  module V1
    # S9 / BE-213, BE-214, BE-215, BE-216, BE-217, BE-221, BE-202 — **parcelas
    # (previsões) da renegociação**.
    #
    # As rotas são **aninhadas** (`/renegotiations/:renegotiation_id/installments`)
    # de propósito: o escopo pai fica visível na própria URL, e não há endpoint que
    # aceite um `renegotiation_installment_id` sem dizer de qual renegociação ele
    # é. No legado as quatro rotas eram planas e a renegociação vinha por
    # parâmetro — foi assim que `renegotiation_id` virou um seletor global.
    #
    # **Toda rota daqui resolve o par (projeto, renegociação) antes de qualquer
    # outra coisa**, e uma parcela de outra renegociação responde o **mesmo 404**
    # de uma parcela inexistente.
    class RenegotiationInstallments < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'renegotiation_installments'

      namespace 'renegotiations/:renegotiation_id/installments' do
        before { authenticate_user! }

        desc 'Lista as parcelas de uma renegociação' do
          detail 'Ordenadas por vencimento, com os pagamentos aninhados. **A paginação funciona** — no ' \
                 'legado `l`/`o` eram calculados e ignorados (D-20).'
          success [code: 200, model: Api::Entities::RenegotiationInstallment]
          is_array true
        end
        params do
          requires :renegotiation_id, type: String
          optional :is_paid, type: Boolean
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 50
        end
        get '' do
          authorize!(RESOURCE, :read)
          renegotiation = fetch_renegotiation!

          scope = RenegotiationInstallmentService.index(
            project: current_project!, renegotiation: renegotiation, params: params
          )[:data]

          Api::Entities::RenegotiationInstallment.represent(paginate(scope).to_a)
        end

        desc 'Prévia dos derivados de uma parcela — SEM gravar (FE-221 / C2)' do
          detail 'Os totais derivados vêm do SERVIDOR, das MESMAS fórmulas que a gravação usa. É o D-09 ' \
                 'aplicado ao painel de parcela: a regra financeira deixa de existir em dois lugares.'
        end
        params do
          requires :renegotiation_id, type: String
          requires :due_date, type: Date
          requires :main_value, type: BigDecimal
          optional :interest_value, type: BigDecimal, default: 0
          optional :monetary_correction_value, type: BigDecimal, default: 0
          optional :multiple, type: Boolean, default: false
          optional :repetitions, type: Integer
          optional :repetition_delay, type: Integer
          optional :repetition_type, type: String, values: ::RenegotiationInstallment::DELAY_TYPES
          optional :replacing_id, type: String,
                                  desc: 'Parcela em EDIÇÃO — sai do cálculo para a prévia não somar duas vezes'
        end
        post :preview do
          authorize!(RESOURCE, :read)
          renegotiation = fetch_renegotiation!

          rascunhos = build_draft_dates(params).map do |data|
            { due_date: data, main_value: params[:main_value], interest_value: params[:interest_value],
              monetary_correction_value: params[:monetary_correction_value] }
          end

          previa = ::Renegotiations::AggregateService.preview(
            renegotiation, draft_installments: rascunhos, replacing_id: params[:replacing_id]
          )

          status 200
          {
            installments: previa.delete(:preview_installments),
            renegotiation: previa
          }
        end

        desc 'Cria uma parcela ou um LOTE de parcelas' do
          detail 'Data ausente → 422 (não 500). Repetições não numéricas → 422 — o `to_i` do legado virava 0 ' \
                 'e a resposta era 200 "criada com sucesso" sem ter criado nada (BE-214).'
        end
        params do
          requires :renegotiation_id, type: String
          requires :due_date, type: Date
          requires :main_value, type: BigDecimal
          optional :interest_value, type: BigDecimal, default: 0
          optional :monetary_correction_value, type: BigDecimal, default: 0
          optional :multiple, type: Boolean, default: false
          optional :repetitions, type: Integer
          optional :repetition_delay, type: Integer
          optional :repetition_type, type: String, values: ::RenegotiationInstallment::DELAY_TYPES
        end
        post '' do
          authorize!(RESOURCE, :create)
          renegotiation = fetch_renegotiation!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:renegotiation_id)
          resultado = RenegotiationInstallmentService.create_batch(renegotiation: renegotiation, attrs: attrs)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] >= 400

          status 201
          {
            created: resultado[:data][:created],
            batch_token: resultado[:data][:batch_token],
            installments: Api::Entities::RenegotiationInstallment.represent(resultado[:data][:installments])
          }
        end

        desc 'Remove um LOTE de parcelas (BE-202)' do
          detail 'Ou o lote inteiro sai, ou nada sai. Corrige D-51: o legado devolvia `inst.blank?` DEPOIS ' \
                 'do `destroy_all` — sucesso quando nada havia e "falha" quando apagou —, e o usuário ' \
                 'reexecutava apagando parcelas a mais.'
        end
        params do
          requires :renegotiation_id, type: String
          requires :renegotiation_installment_ids, type: Array[String]
        end
        delete :batch do
          authorize!(RESOURCE, :destroy)
          renegotiation = fetch_renegotiation!

          resultado = ::Renegotiations::BatchDestroyInstallments.call(
            renegotiation: renegotiation, installment_ids: params[:renegotiation_installment_ids]
          )
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] >= 400
          resultado[:data]
        end

        desc 'Detalhe de uma parcela'
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
        end
        get ':id' do
          authorize!(RESOURCE, :read)
          Api::Entities::RenegotiationInstallment.represent(fetch_installment!)
        end

        desc 'Atualiza uma parcela' do
          detail 'Recalcula e renumera. **Aumentar o valor REABRE parcela quitada** — `is_paid` é derivado ' \
                 'de `pending_value <= 0`, e nada mais.'
        end
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
          optional :due_date, type: Date
          optional :main_value, type: BigDecimal
          optional :interest_value, type: BigDecimal
          optional :monetary_correction_value, type: BigDecimal
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          parcela = fetch_installment!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id, :renegotiation_id)
          resultado = RenegotiationInstallmentService.update_installment(installment: parcela, attrs: attrs)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::RenegotiationInstallment.represent(resultado[:data])
        end

        desc 'Remove uma parcela — barrada por pagamento, COM o motivo'
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
        end
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          parcela = fetch_installment!

          resultado = RenegotiationInstallmentService.destroy_installment(installment: parcela)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end

      helpers do
        # **A forma canônica do C1 no segundo nível.** Renegociação de outro
        # projeto e renegociação inexistente respondem o MESMO 404 — distinguir
        # 403 de 404 transformaria o endpoint num oráculo de existência de ids.
        def fetch_renegotiation!
          resultado = RenegotiationService.show(project: current_project!, id: params[:renegotiation_id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end

        def fetch_installment!
          renegotiation = fetch_renegotiation!
          parcela = RenegotiationInstallmentService.find_in(renegotiation, params[:id])
          if parcela.nil?
            error!({ error: 'not_found', message: 'Parcela não encontrada.' }, 404)
          end
          parcela
        end

        # As datas do rascunho saem da MESMA função que a gravação usa, para que a
        # prévia e o `POST` não possam divergir (teste 4.13).
        def build_draft_dates(params)
          attrs = { due_date: params[:due_date], multiple: params[:multiple], repetitions: params[:repetitions],
                    repetition_delay: params[:repetition_delay], repetition_type: params[:repetition_type] }
          datas = ::Renegotiations::CreateInstallmentsBatch.build_dates(attrs)
          error!(error_payload_for(datas), datas[:status]) if datas.is_a?(Hash)
          datas
        end
      end
    end
  end
end
