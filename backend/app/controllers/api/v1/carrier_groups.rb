# frozen_string_literal: true

module Api
  module V1
    # S3 / BE-072, BE-073, BE-074 — **grupos de portadores**. Catálogo GLOBAL.
    #
    # **Sem `current_project!`** (C1, regra 4).
    #
    # Ordenar por título respondia **500** no legado (D-21): o controller
    # chamava `CarrierGroup.prepare_ordering`, que o model nunca definiu. Aqui a
    # allowlist é dado (`Sfg::Sortable`) e chave desconhecida é ignorada.
    class CarrierGroups < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'carrier_groups'

      namespace :carrier_groups do
        before { authenticate_user! }

        desc 'Lista grupos de portadores' do
          summary 'Grupos de portadores'
          detail 'Ordenação por título FUNCIONA (o legado respondia 500 — D-21). Paginação aplicada.'
        end
        params do
          optional :q, type: String
          optional :active, type: Boolean
          optional :ordering_keys, type: Array[String], desc: 'title | key | carriers_count | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(CarrierGroupService, Api::Entities::CarrierGroup)
        end

        desc 'Detalhe de um grupo'
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(CarrierGroupService, Api::Entities::CarrierGroup, params[:id])
        end

        desc 'Cria um grupo'
        params do
          requires :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(CarrierGroupService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::CarrierGroup, expected: 201)
        end

        desc 'Atualiza um grupo'
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(CarrierGroupService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::CarrierGroup, expected: 200)
        end

        desc 'Remove um grupo' do
          detail 'Grupo com portadores → **422 no servidor** (BE-073), e o `group_id` dos portadores PERMANECE. ' \
                 'No legado o botão sumia pela contagem divergente e a exclusão passava assim mesmo, deixando órfão.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = CarrierGroupService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
