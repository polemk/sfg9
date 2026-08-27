# frozen_string_literal: true

module Api
  module V1
    # S3 / BE-075, BE-076 — **segmentos**. Catálogo GLOBAL.
    #
    # **Este endpoint NÃO chama `current_project!`, de propósito** (contrato C1,
    # regra 4 de `§0.6`). Quem vier da S4 tende a "consertar" isto aplicando
    # escopo — e aí um segmento cadastrado no projeto A sumiria do projeto B,
    # enquanto `projects.segment_id` continuaria apontando para ele.
    #
    # Leitura: qualquer autenticado, inclusive Colaborador (DEC-18.4).
    # Escrita: OG/Admin/Gerente, decidido pela `Authorization::Matrix` **no
    # servidor** — o legado tinha o gate só na view (D-23).
    class Segments < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'segments'

      namespace :segments do
        before { authenticate_user! }

        desc 'Lista segmentos' do
          summary 'Segmentos'
          detail 'Catálogo GLOBAL — sem escopo de projeto. Paginação e ordenação APLICADAS (D-20).'
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :active, type: Boolean, desc: 'Só os ativos'
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(SegmentService, Api::Entities::Segment)
        end

        desc 'Detalhe de um segmento'
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(SegmentService, Api::Entities::Segment, params[:id])
        end

        desc 'Cria um segmento' do
          detail 'Fecha o D-21: no legado `user_id` estava fora do `permit` e a criação falhava 100% das vezes. ' \
                 'O autor vem da SESSÃO; o `user_id` do corpo é ignorado.'
        end
        params do
          requires :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(SegmentService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::Segment, expected: 201)
        end

        desc 'Atualiza um segmento'
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(SegmentService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::Segment, expected: 200)
        end

        desc 'Remove um segmento' do
          detail 'Bloqueado por projeto vinculado → 422 REAL. O legado respondia `:ok` mesmo sem excluir (D-24).'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = SegmentService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
