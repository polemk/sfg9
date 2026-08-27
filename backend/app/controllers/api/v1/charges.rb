# frozen_string_literal: true

module Api
  module V1
    # S6 / **BE-187**, **BE-188**, **BE-189** — **cobranças e recibos**.
    # Dono por **DEC-63**.
    #
    # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
    #
    # `charges`, `receipts` e `remunerations` **não existem** no banco de
    # produção: as migrations que as criam estão entre as 24 que nunca subiram.
    # Regra espelhada do código de 2022, sem corrigir o que parecer errado, e o
    # golden desta família trava a **leitura do código** — não um comportamento
    # observado.
    #
    # ## Contrato C1 e o D-18
    #
    # `project = current_project!` em toda ação. E "Faturado" bloqueia **no
    # servidor**: no legado o bloqueio existia só na tela
    # (`charges/show/_body.js.erb`) e a API aceitava a alteração de um pacote
    # já emitido.
    #
    # ## Dependência da S8, declarada em vez de escondida
    #
    # Recibos dependem de `Remuneration` (**S8**). Enquanto o model não existir,
    # os endpoints de recibo respondem **422 nomeando a fatia** — não 500, e não
    # uma lista vazia que faria parecer que não há nada a faturar.
    class Charges < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'charges'

      # **Antes do `rescue_from StandardError`, e por isso mesmo.** Erro de
      # validação de parâmetro do Grape é `StandardError`: sem este handler o
      # `rescue_from` abaixo o engolia e um `state` fora do domínio, ou um
      # `date` ausente, respondia **500**. O cliente não tem como distinguir
      # "eu mandei errado" de "o servidor quebrou" — e o `api/v1/base.rb:214`,
      # que já trata isto com 400, nunca é alcançado porque o handler local
      # vence o do pai.
      rescue_from Grape::Exceptions::ValidationErrors do |e|
        error!({ error: 'invalid_request', message: e.message }, 400)
      end

      rescue_from StandardError do |e|
        Rails.logger.error("[Api::V1::Charges] #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}")
        error!({ error: 'internal_error',
                 message: 'Não foi possível concluir a operação com as cobranças. Tente novamente.' }, 500)
      end

      namespace :charges do
        before { authenticate_user! }

        desc 'Lista as cobranças do projeto corrente' do
          summary 'Cobranças'
          detail 'Paginação REAL (D-20): no legado o limite era fixo de 1000 no cliente e não havia ' \
                 'nenhum no servidor. O filtro de ano aceita VAZIO (FE-180) — sem isso era impossível ' \
                 'ver todas as cobranças de uma vez.'
          success [code: 200, model: Api::Entities::Charge]
          is_array true
        end
        params do
          optional :charge_id, type: String, desc: 'Filtro por id — aplicado DENTRO do escopo'
          optional :state, type: String, values: ::Charge::STATES, desc: 'editing | available | done'
          optional :month, type: Integer, values: 1..12
          optional :year, type: Integer, desc: 'Vazio = todas as cobranças'
          optional :ordering_keys, type: Array[String], desc: 'date | state | value | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = ::Charges::ChargeService.index(project: project, params: params)[:data]
          # ⛔ cross-project: id de outro projeto devolve VAZIO.
          if params[:charge_id].present?
            scope = if ::Charges::ChargeService.uuid?(params[:charge_id])
                      scope.where(id: params[:charge_id])
                    else
                      scope.none
                    end
          end

          Api::Entities::Charge.represent(paginate(scope).to_a)
        end

        desc 'Cria uma cobrança' do
          detail 'Nasce em `editing` — nunca em `done`. A data padrão da tela é hoje + 30 dias (FE-186), ' \
                 'e ela é decisão de INTERFACE: o servidor exige a data explicitamente.'
        end
        params do
          requires :date, type: Date
          optional :state, type: String, values: [::Charge::STATE_EDITING, ::Charge::STATE_AVAILABLE],
                           default: ::Charge::STATE_EDITING,
                           desc: '`done` NÃO é aceito na criação: um pacote nasce aberto'
        end
        post '' do
          authorize!(RESOURCE, :create)
          require_not_readonly!
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          resultado = ::Charges::ChargeService.create(project: project, attrs: attrs, actor: current_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 201

          status 201
          Api::Entities::Charge.represent(resultado[:data])
        end

        route_param :id, type: String do
          desc 'Detalhe de uma cobrança' do
            detail '⛔ cross-project: id de outro projeto responde EXATAMENTE como id inexistente (404).'
          end
          get '' do
            authorize!(RESOURCE, :read)
            project = current_project!

            resultado = ::Charges::ChargeService.show(project: project, id: params[:id])
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

            Api::Entities::Charge.represent(resultado[:data])
          end

          desc 'Extrato da cobrança: totais por remuneração' do
            detail 'Uma consulta AGREGADA. O legado tinha `# TODO #7388 otimizar a busca` no código e ' \
                   'montava os totais em Ruby, linha a linha (FE-182).'
          end
          get 'statement' do
            authorize!(RESOURCE, :read)
            project = current_project!

            resultado = ::Charges::ChargeService.statement(project: project, id: params[:id])
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

            {
              charge: Api::Entities::Charge.represent(resultado[:data][:charge]).as_json,
              statement: resultado[:data][:statement]
            }
          end

          desc 'Recibos vinculados e candidatos' do
            detail 'Candidato é toda operação SEM recibo cujo tipo tem remuneração cadastrada. O `temp_id` ' \
                   'é a identidade estável antes de o recibo existir — é por ele que a tela casa marcado × ' \
                   'persistido (FE-184).'
          end
          get 'receipts' do
            authorize!(RESOURCE, :read)
            project = current_project!

            charge = ::Charges::ChargeService.find(project, params[:id])
            error!({ error: 'not_found', message: 'Cobrança não encontrada.' }, 404) if charge.nil?

            resultado = ::Charges::ReceiptGenerator.candidates(project: project, charge: charge)
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
            resultado[:data]
          end

          desc 'Define os recibos do pacote, EM LOTE' do
            detail 'A lista enviada é o estado FINAL: o que não está nela é removido. Tudo numa transação — ' \
                   'falha reverte o lote inteiro e a tela recarrega do servidor (FE-185). ' \
                   'Cobrança `done` recusa no SERVIDOR (D-18).'
          end
          params do
            requires :temp_ids, type: Array[String], desc: 'Estado final da seleção'
          end
          put 'receipts' do
            authorize!(RESOURCE, :update)
            require_not_readonly!
            project = current_project!

            resultado = ::Charges::BulkReceiptsService.call(
              project: project, charge_id: params[:id], temp_ids: params[:temp_ids], actor: current_user
            )
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

            Api::Entities::Charge.represent(resultado[:data])
          end

          desc 'Atualiza uma cobrança' do
            detail 'Cobrança `done` (Faturado) recusa qualquer alteração NO SERVIDOR — corrige o D-18.'
          end
          params do
            optional :date, type: Date
            optional :state, type: String, values: ::Charge::STATES
          end
          put '' do
            authorize!(RESOURCE, :update)
            require_not_readonly!
            project = current_project!

            attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
            resultado = ::Charges::ChargeService.update(project: project, id: params[:id],
                                                        attrs: attrs, actor: current_user)
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

            Api::Entities::Charge.represent(resultado[:data])
          end

          desc 'Remove uma cobrança' do
            detail 'Bloqueada por recibo vinculado → 422 REAL. Cobrança `done` também recusa.'
          end
          delete '' do
            authorize!(RESOURCE, :destroy)
            require_not_readonly!
            project = current_project!

            resultado = ::Charges::ChargeService.destroy(project: project, id: params[:id])
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
            resultado[:data]
          end
        end
      end
    end
  end
end
