# frozen_string_literal: true

module Api
  module V1
    # S3 / BE-077, BE-078 — **subsegmentos**. Catálogo GLOBAL.
    #
    # **Sem `current_project!`** (C1, regra 4). E **sem acoplamento com
    # `Segment`** (DC-13): no legado `SubSegment.prepare_ordering` chamava
    # `Segment.get_ordering_key`, de modo que mudar a allowlist de um catálogo
    # mudava a do outro por acidente.
    class SubSegments < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'sub_segments'

      namespace :sub_segments do
        before { authenticate_user! }

        desc 'Lista subsegmentos' do
          summary 'Subsegmentos'
          detail 'Catálogo GLOBAL e independente de `segments` (DC-13). Paginação e ordenação APLICADAS.'
        end
        params do
          optional :q, type: String
          optional :active, type: Boolean
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(SubSegmentService, Api::Entities::SubSegment)
        end

        desc 'Detalhe de um subsegmento'
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(SubSegmentService, Api::Entities::SubSegment, params[:id])
        end

        desc 'Cria um subsegmento'
        params do
          requires :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(SubSegmentService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::SubSegment, expected: 201)
        end

        desc 'Atualiza um subsegmento'
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(SubSegmentService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::SubSegment, expected: 200)
        end

        desc 'Remove um subsegmento' do
          detail 'Bloqueado por projeto vinculado → 422 REAL (BE-078 / D-24).'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = SubSegmentService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
