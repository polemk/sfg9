# frozen_string_literal: true

module Api
  module V1
    # S6 / **BE-150**…**BE-153**, **FE-171** — **o borderô**.
    #
    # ## Contrato C1 — o escopo é uma linha visível em toda ação
    #
    # `project = current_project!` aparece em cada bloco. Um endpoint desta
    # fatia sem essa linha é vazamento de tenant. **`project_id` no corpo nem é
    # declarado** — é a ausência que fecha a família D-01/D-16/D-29/D-76/D-100,
    # em que o legado descartava o filtro de projeto assim que chegava um id por
    # parâmetro.
    #
    # **Id de outro projeto responde igual a id inexistente** (404 no `show`,
    # vazio na lista). Distinguir 403 de 404 transformaria o endpoint num
    # oráculo de existência de ids.
    #
    # ## Contrato C2 — `#preview` e `#create` passam pelo MESMO serviço
    #
    # `POST /receivables/preview` monta o mesmo `Input`, chama o mesmo
    # `Receivables::Calculator` e devolve o mesmo entity de derivados que a
    # gravação. Há request spec que envia o mesmo payload aos dois e compara
    # campo a campo — divergência de um único campo reprova. É o que fecha o
    # **D-09** na raiz: no legado a prévia era uma reimplementação parcial da
    # fórmula em JavaScript.
    #
    # ## O `rescue_from` local (tarefa 2.31 / F-3)
    #
    # `api/v1/base.rb:57-75` tem um `rescue_from :all` que devolve **backtrace
    # ao cliente** e cita "API ERROR - POLEMK WHATS". Num endpoint financeiro
    # isso vaza caminho de arquivo e estrutura interna num 500. Aqui há
    # `rescue_from` próprio; o global **não** é alterado (Princípio 6b) e está
    # registrado como **F-3** em `upstream-flags.md`.
    class Receivables < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'receivables'

      # **Antes do `rescue_from StandardError`, e por isso mesmo.** Erro de
      # validação de parâmetro do Grape é `StandardError`: sem este handler o
      # `rescue_from` abaixo o engolia e um `date` malformado no corpo
      # respondia **500**, indistinguível de servidor quebrado. O
      # `api/v1/base.rb:214` já trata isto com 400, mas nunca é alcançado —
      # handler local vence o do pai. Medido rodando o mesmo payload contra os
      # dois endpoints da fatia (`charges` tinha o defeito idêntico).
      rescue_from Grape::Exceptions::ValidationErrors do |e|
        error!({ error: 'invalid_request', message: e.message }, 400)
      end

      # **S7 / B-09 — antes do `rescue_from StandardError`, pelo mesmo motivo do
      # handler acima.** Desde a S7 o `after_create` de `RiskOperation` lança o
      # movimento "Liberação do Recurso", e o borderô de tipo SEM pré-faturamento
      # cria a operação (`Receivables::RiskSyncService`). Se o catálogo de
      # referência não estiver semeado, `RiskMovementType.release` levanta
      # {RiskMovementType::MissingFunctionalType} — que é `StandardError` e, sem
      # esta linha, virava o 500 genérico "Não foi possível concluir a operação".
      #
      # A mensagem da exceção **já é para humano**: nomeia a chave que falta e
      # diz o que rodar. Engoli-la num 500 genérico esconde exatamente o que a
      # B-09 existe para expor (no legado isto era `NoMethodError` em `nil.id`,
      # e ainda por cima **depois** do INSERT).
      #
      # Medido: `spec/requests/api/v1/receivables_spec.rb:440` respondia 500.
      rescue_from RiskMovementType::MissingFunctionalType do |e|
        error!({ error: 'unprocessable_entity', message: e.message }, 422)
      end

      # Não vaza backtrace. A mensagem é genérica para o cliente e completa no
      # log — que é onde ela serve para alguém.
      rescue_from StandardError do |e|
        Rails.logger.error("[Api::V1::Receivables] #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}")
        error!({ error: 'internal_error',
                 message: 'Não foi possível concluir a operação com os borderôs. Tente novamente.' }, 500)
      end

      helpers do
        # As tarifas chegam como array de objetos. Os **classificadores nunca
        # vêm do cliente**: são resolvidos do `MovementKind` no servidor —
        # aceitá-los do corpo deixaria a tela escolher a base do IOF.
        def tax_payload
          params[:taxes]&.map { |t| t.slice(:id, :movement_kind_id, :value).symbolize_keys }
        end

        def entry_attrs
          declared(params, include_missing: false).symbolize_keys.except(:id, :taxes, :page, :per_page)
        end
      end

      namespace :receivables do
        before { authenticate_user! }

        # ------------------------------------------------------------------
        desc 'Lista os borderôs do projeto corrente' do
          summary 'Borderôs'
          detail 'Escopo por `current_project!`. Paginação e ordenação APLICADAS (D-20): no legado ' \
                 '`limit`/`offset` eram lidos e descartados, e a última página ia para o lugar errado. ' \
                 'Limite de data ausente OMITE a cláusula — fim de `DateTime.dinosaurs`/`.mars` (OPS-158).'
          success [code: 200, model: Api::Entities::ReceivableEntry]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por portador, número do borderô ou descrição (ILIKE com bind)'
          optional :receivable_id, type: String, desc: 'Filtro por id — aplicado DENTRO do escopo (D-16)'
          optional :wallet_id, type: String
          optional :carrier_id, type: String
          optional :company_id, type: String
          optional :status, type: String, values: ::Entry::STATUSES, desc: 'ok | difference'
          optional :date_from, type: Date, desc: 'Ausente OMITE a cláusula'
          optional :date_to, type: Date, desc: 'Ausente OMITE a cláusula'
          optional :ordering_keys, type: Array[String],
                                   desc: 'carrier | wallet | date | bruto | tarifas | liquido | titulos | pmr | cet | cetsf'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = ::Receivables::SearchService.index(project: project, params: params)[:data]
          # ⛔ cross-project: id malformado ou de outro projeto devolve VAZIO.
          # Nunca a lista inteira, nunca 403.
          if params[:receivable_id].present?
            scope = if ::Receivables::SearchService.uuid?(params[:receivable_id])
                      scope.where(id: params[:receivable_id])
                    else
                      scope.none
                    end
          end

          Api::Entities::ReceivableEntry.represent(paginate(scope).to_a)
        end

        # ------------------------------------------------------------------
        desc 'Totais da consulta corrente' do
          detail 'Os mesmos filtros da lista, agregados numa consulta só. Existe para que o rodapé da ' \
                 'tela não precise carregar 28 mil linhas para somar.'
        end
        params do
          optional :q, type: String
          optional :wallet_id, type: String
          optional :carrier_id, type: String
          optional :company_id, type: String
          optional :status, type: String, values: ::Entry::STATUSES
          optional :date_from, type: Date
          optional :date_to, type: Date
        end
        get 'summary' do
          authorize!(RESOURCE, :read)
          project = current_project!

          # S15: a consulta saiu daqui para `SearchService.totals`. O dashboard
          # (`NEW-002`) mostra o MESMO "total operado", e com o `SUM` no endpoint
          # ele teria de reescrever a fórmula — a segunda implementação que o
          # contrato C2 existe para impedir (D-09). O número não mudou.
          ::Receivables::SearchService.totals(project, params)
        end

        # ------------------------------------------------------------------
        desc 'Prévia do cálculo, SEM PERSISTIR NADA' do
          summary 'Prévia do borderô (C2)'
          detail 'Monta o mesmo `Input`, chama o mesmo `Receivables::Calculator` e devolve os mesmos ' \
                 'derivados que a gravação. É o que impede a prévia e o valor gravado de divergirem (D-09). ' \
                 'Combinação que produziria Infinity/NaN responde 422 aqui e na gravação, pelo mesmo motivo (D-10).'
          success [code: 200, model: Api::Entities::ReceivableDerived]
        end
        params do
          requires :valor_bruto, type: BigDecimal
          optional :vlr_bruto_recusado, type: BigDecimal, default: 0
          requires :qtd_titulos, type: Integer
          optional :qtd_recusada, type: Integer, default: 0
          requires :prz_med_pond_emp, type: BigDecimal, desc: 'Em dias. Precisa ser maior que zero'
          requires :prz_med_pond_bco, type: BigDecimal, desc: 'Em dias. Precisa ser maior que zero'
          optional :float_acordado, type: BigDecimal, default: 0
          optional :cst_efetivo_acordado, type: BigDecimal, default: 0
          optional :recompra, type: BigDecimal, default: 0
          optional :retencao, type: BigDecimal, default: 0
          optional :fomento, type: BigDecimal, default: 0
          optional :outros, type: BigDecimal, default: 0
          optional :date, type: Date, desc: 'Data da operação — decide a alíquota de IOF vigente (BE-160)'
          optional :taxes, type: Array do
            requires :movement_kind_id, type: String
            requires :value, type: BigDecimal
          end
        end
        post 'preview' do
          authorize!(RESOURCE, :read)
          current_project!

          atributos = declared(params, include_missing: false).symbolize_keys
          resultado = ::Receivables::PreviewService.call(
            attrs: atributos, taxes: params[:taxes] || [], operation_date: params[:date]
          )
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          # O default do Grape para `post` é **201**. A prévia não cria nada:
          # devolver "Created" seria mentira de contrato, e o front usa o status
          # para distinguir prévia de gravação.
          status 200
          Api::Entities::ReceivableDerived.represent(resultado[:data])
        end

        # ------------------------------------------------------------------
        desc 'Cria um borderô' do
          detail 'Borderô e tarifas numa ÚNICA transação, com UM recálculo. Corrige o D-11: no legado o ' \
                 'controller salvava duas vezes e a operação de risco nascia com o líquido SEM as tarifas. ' \
                 'O `user_id` do corpo é ignorado — o autor é o da sessão (BE-182).'
          success [code: 201, model: Api::Entities::ReceivableEntry]
        end
        params do
          requires :date, type: Date
          requires :company_id, type: String
          requires :carrier_id, type: String
          requires :wallet_id, type: String
          requires :receivable_kind_id, type: String
          requires :resource_source_id, type: String
          requires :valor_bruto, type: BigDecimal
          requires :qtd_titulos, type: Integer
          requires :prz_med_pond_emp, type: BigDecimal
          requires :prz_med_pond_bco, type: BigDecimal
          optional :vlr_bruto_recusado, type: BigDecimal, default: 0
          optional :qtd_recusada, type: Integer, default: 0
          optional :float_acordado, type: BigDecimal, default: 0
          optional :cst_efetivo_acordado, type: BigDecimal, default: 0
          optional :recompra, type: BigDecimal, default: 0
          optional :retencao, type: BigDecimal, default: 0
          optional :fomento, type: BigDecimal, default: 0
          optional :outros, type: BigDecimal, default: 0
          optional :nominal_tax, type: BigDecimal
          optional :data_credito, type: Date
          optional :nro_bordero, type: String, desc: 'STRING: produção tem `F-76`, `48-49`, `1540962/20`'
          optional :contrato, type: String
          optional :description, type: String
          optional :observacoes, type: String, desc: 'Visível por DEC-52'
          optional :risk_operation_subtype_id, type: String, desc: 'Opcional — "Não associar"'
          optional :taxes, type: Array do
            optional :id, type: String
            requires :movement_kind_id, type: String
            requires :value, type: BigDecimal
          end
        end
        post '' do
          authorize!(RESOURCE, :create)
          require_not_readonly!
          project = current_project!

          resultado = ::Receivables::CreateService.call(
            project: project, attrs: entry_attrs, actor: current_user, taxes: tax_payload || []
          )
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 201

          status 201
          Api::Entities::ReceivableEntry.represent(resultado[:data])
        end

        # ------------------------------------------------------------------
        route_param :id, type: String do
          desc 'Detalhe de um borderô' do
            detail '⛔ cross-project: id de outro projeto responde EXATAMENTE como id inexistente (404).'
          end
          get '' do
            authorize!(RESOURCE, :read)
            project = current_project!

            resultado = ::Receivables::SearchService.show(project: project, id: params[:id])
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

            Api::Entities::ReceivableEntry.represent(resultado[:data])
          end

          desc 'Atualiza um borderô' do
            detail 'Payload SEM a chave `taxes` preserva as tarifas existentes. Com a chave, a lista passa a ' \
                   'ser a enviada e o que saiu é apagado — é a exclusão pendente da DEC-72. ' \
                   'O subtipo de operação é IMUTÁVEL na edição.'
          end
          params do
            optional :date, type: Date
            optional :company_id, type: String
            optional :carrier_id, type: String
            optional :wallet_id, type: String
            optional :receivable_kind_id, type: String
            optional :resource_source_id, type: String
            optional :valor_bruto, type: BigDecimal
            optional :qtd_titulos, type: Integer
            optional :prz_med_pond_emp, type: BigDecimal
            optional :prz_med_pond_bco, type: BigDecimal
            optional :vlr_bruto_recusado, type: BigDecimal
            optional :qtd_recusada, type: Integer
            optional :float_acordado, type: BigDecimal
            optional :cst_efetivo_acordado, type: BigDecimal
            optional :recompra, type: BigDecimal
            optional :retencao, type: BigDecimal
            optional :fomento, type: BigDecimal
            optional :outros, type: BigDecimal
            optional :nominal_tax, type: BigDecimal
            optional :data_credito, type: Date
            optional :nro_bordero, type: String
            optional :contrato, type: String
            optional :description, type: String
            optional :observacoes, type: String
            optional :taxes, type: Array do
              optional :id, type: String
              requires :movement_kind_id, type: String
              requires :value, type: BigDecimal
            end
          end
          put '' do
            authorize!(RESOURCE, :update)
            require_not_readonly!
            project = current_project!

            resultado = ::Receivables::UpdateService.call(
              project: project, id: params[:id], attrs: entry_attrs, actor: current_user,
              taxes: params.key?(:taxes) ? (tax_payload || []) : :unchanged
            )
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

            Api::Entities::ReceivableEntry.represent(resultado[:data])
          end

          desc 'Remove um borderô' do
            detail 'Exclusão em transação, levando junto tarifas e a operação de risco gerada. ' \
                   'Corrige o D-24: no legado os DOIS ramos do ternário respondiam `:ok`, e a tela dizia ' \
                   '"removido com sucesso" sem ter removido.'
          end
          delete '' do
            authorize!(RESOURCE, :destroy)
            require_not_readonly!
            project = current_project!

            resultado = ::Receivables::SearchService.destroy(project: project, id: params[:id])
            error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

            resultado[:data]
          end
        end
      end

      # ------------------------------------------------------------------
      # OPS-154 — os textos de ajuda dos campos do formulário.
      # Campo sem chave NÃO exibe indicador de ajuda; o conteúdo do legado é
      # integralmente placeholder (Q-B20), então nasce vazio.
      namespace :receivable_help_texts do
        before { authenticate_user! }

        desc 'Textos de ajuda dos campos do formulário de borderô'
        get '' do
          authorize!(RESOURCE, :read)
          ::Receivables::HelpTexts.all
        end
      end
    end
  end
end
