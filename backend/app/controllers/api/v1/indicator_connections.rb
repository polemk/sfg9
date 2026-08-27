# frozen_string_literal: true

module Api
  module V1
    # S10 / BE-707, BE-709, BE-710, BE-711, BE-717 — **indicadores específicos
    # do projeto**.
    #
    # É a tela "Indicadores específicos" do grupo Projeto. **Escopado por
    # projeto** (contrato C1): toda ação declara `project = current_project!`
    # numa linha visível, e nenhum id de projeto vem do corpo.
    #
    # ## O que este endpoint substitui
    #
    # O `Pub::ProjectIndicatorConnectionsController` do legado tem **6 chamadas a
    # `constantize` sobre parâmetro do usuário** (`:24, :26, :47, :49, :68, :70`)
    # — qualquer classe Ruby carregada podia ser instanciada por URL. Aqui não há
    # tipo dinâmico: o recurso é `Indicator`, escrito no código.
    #
    # Três rotas daquele controller **não** viram endpoint aqui, e cada uma tem a
    # evidência registrada no `parity-ledger.md`:
    #
    # - `GET /project_indicator_connections` (**BE-712**) — template inexistente;
    # - `GET /project_indicator_connections/:id/edit` (**BE-713**) — diretório
    #   `new/` inexistente;
    # - `DELETE /project_indicator_connections/:id` (**BE-714**) — diretório
    #   `destroy/` inexistente e `@connection` **nunca setado** (o `before_action`
    #   seta `@connections`, plural): `NoMethodError` antes do template;
    # - `GET .../connections` (**BE-708**) — `@connection_type.all`: **todos os
    #   indicadores de todos os projetos**, sem escopo e sem autorização, e
    #   **nenhuma view o chama**.
    class IndicatorConnections < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'indicator_connections'

      namespace :indicator_connections do
        before { authenticate_user! }

        desc 'Indicadores que este projeto alcança' do
          summary 'Indicadores específicos'
          detail 'Globais + específicos DESTE projeto, com a marca de conectado. A busca passa a ' \
                 'funcionar: no legado os ramos `if connection_type == "Carrier"/"Project"` nunca casam ' \
                 'com "Indicator", então `q`, limit e offset eram ignorados (o front chama com l=200).'
          success [code: 200, model: Api::Entities::IndicatorConnection]
          is_array true
        end
        params do
          optional :q, type: String
          optional :active, type: Boolean
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          projeto = current_project!

          escopo = ::Indicators::ConnectionService.connectable(project: projeto, params: params)
          lista = paginate(escopo).to_a
          Api::Entities::IndicatorConnection.represent(
            lista,
            connected_ids: ::Indicators::ConnectionService.connected_ids(projeto),
            entry_usage: ::Indicators::IndicatorService.entry_counts(lista.map(&:id))
          )
        end

        desc 'Conecta indicadores ao projeto' do
          detail 'BE-709 — transação e RELATÓRIO POR ITEM. No legado o laço reatribuía `@connection` a ' \
                 'cada volta e nem verificava o `save`: conectar 3 indicadores com 1 falha podia reportar ' \
                 'sucesso, porque só a última conexão era inspecionada depois.'
        end
        params { requires :indicator_ids, type: Array[String], desc: 'UUIDs dos indicadores' }
        post 'connect' do
          authorize!(RESOURCE, :create)
          projeto = current_project!

          resultado = ::Indicators::ConnectionService.connect(project: projeto, indicator_ids: params[:indicator_ids],
                                                            actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          # 200, não o 201 que o Grape dá por padrão ao POST: conectar é
          # **definir estado** e é idempotente — não há recurso novo com URL
          # própria para apontar.
          status 200
          resultado[:data]
        end

        desc 'Desconecta indicadores do projeto' do
          detail 'Q-R31, replicado: desconectar ESCONDE o indicador da grade e NÃO apaga lançamento — ' \
                 'reconectar traz o histórico de volta inteiro. Par inexistente é no-op idempotente, ' \
                 'não `nil.destroy` → 500.'
        end
        params { requires :indicator_ids, type: Array[String], desc: 'UUIDs dos indicadores' }
        post 'disconnect' do
          authorize!(RESOURCE, :destroy)
          projeto = current_project!

          resultado = ::Indicators::ConnectionService.disconnect(project: projeto, indicator_ids: params[:indicator_ids],
                                                               actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          status 200
          resultado[:data]
        end

        desc 'Exclui um indicador ESPECÍFICO deste projeto' do
          detail 'BE-711 — a conexão sai primeiro (o `restrict_with_error` depende disso) e o indicador vai ' \
                 'para a exclusão LÓGICA. Indicador GLOBAL é recusado com 422: no legado esse mesmo ramo ' \
                 'levantava `NoMethodError`, porque `@connection` vinha do `before_action` e era uma ' \
                 '`Relation`. O FIXME do arquivo registra que a issue #7102 corrigia um id errado que ' \
                 'DELETAVA O INDICADOR INCORRETO.'
        end
        params { requires :indicator_id, type: String, desc: 'UUID do indicador específico' }
        delete ':indicator_id' do
          authorize!(RESOURCE, :destroy)
          projeto = current_project!

          resultado = ::Indicators::ConnectionService.destroy_specific(project: projeto,
                                                                     indicator_id: params[:indicator_id],
                                                                     actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end
    end
  end
end
