# frozen_string_literal: true

module Api
  module V1
    # S6 / **BE-186**, **BE-446**, **BE-447**, **BE-448** — tipos de
    # movimentação (as tarifas do borderô). **Catálogo GLOBAL.**
    #
    # É o catálogo que decide em qual bucket a tarifa cai — e, por consequência,
    # a base do IOF e todos os CETs. Errar aqui muda número em 28 mil borderôs.
    #
    # ## O que muda em relação ao legado
    #
    # - **BE-447** — dois classificadores marcados devolvem 422 com mensagem
    #   pt-BR. No legado a mensagem era o erro cru "Múltiplos tipos Pode ter
    #   apenas um dos tipos definidos", porque o `errors.add` usava uma frase
    #   como nome de atributo.
    # - **BE-448** — remoção com tarifa vinculada devolve **422 nomeando o
    #   vínculo**; o `restrict_with_error` do legado levantava e virava 500.
    # - **BE-446** — a chave é derivada do título na criação e **congelada**. No
    #   legado ela continuava no `permit` e a tela a reescrevia: título e chave
    #   divergiam na primeira edição.
    # - `kind` tem domínio fechado (`credit`/`debit`); no legado era texto livre.
    class MovementKinds < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'movement_kinds'

      namespace :movement_kinds do
        before { authenticate_user! }

        desc 'Lista tipos de movimentação' do
          summary 'Tipos de movimentação'
          detail 'Catálogo GLOBAL. `for_operation=true` devolve só os que aparecem na lista de tarifas ' \
                 'do borderô — é o único dos flags de exibição do legado que tem leitor.'
          success [code: 200, model: Api::Entities::MovementKind]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :active, type: Boolean
          optional :for_operation, type: Boolean, desc: 'Só os que entram na lista de tarifas do borderô'
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 100
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(MovementKindService, Api::Entities::MovementKind)
        end

        desc 'Detalhe de um tipo de movimentação'
        params { requires :id, type: String, desc: 'UUID' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(MovementKindService, Api::Entities::MovementKind, params[:id])
        end

        desc 'Cria um tipo de movimentação' do
          detail 'No máximo UM classificador de taxa (BE-447): AdValorem, Deságio, IOF ou Liquidação. ' \
                 'Dois marcados → 422 com mensagem pt-BR.'
        end
        params do
          requires :title, type: String
          optional :integration_key, type: String
          optional :kind, type: String, values: ::MovementKind::KINDS, desc: 'credit | debit'
          optional :is_active, type: Boolean, default: true
          optional :is_operation, type: Boolean, default: false
          optional :is_title, type: Boolean, default: false, desc: 'Portado SEM consumidor (D-74, Q-B13)'
          optional :is_advalorem, type: Boolean, default: false
          optional :is_desagio, type: Boolean, default: false
          optional :is_iof, type: Boolean, default: false
          optional :is_liquidation, type: Boolean, default: false, desc: 'Portado SEM consumidor (D-74, Q-B13)'
        end
        post '' do
          authorize!(RESOURCE, :create)
          require_not_readonly!
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(MovementKindService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::MovementKind, expected: 201)
        end

        desc 'Atualiza um tipo de movimentação'
        params do
          requires :id, type: String
          optional :title, type: String
          optional :kind, type: String, values: ::MovementKind::KINDS
          optional :is_active, type: Boolean
          optional :is_operation, type: Boolean
          optional :is_title, type: Boolean
          optional :is_advalorem, type: Boolean
          optional :is_desagio, type: Boolean
          optional :is_iof, type: Boolean
          optional :is_liquidation, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          require_not_readonly!
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(MovementKindService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::MovementKind, expected: 200)
        end

        desc 'Remove um tipo de movimentação' do
          detail 'Bloqueado por tarifa vinculada → 422 REAL nomeando o vínculo (BE-448 / D-24).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          require_not_readonly!
          result = MovementKindService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
