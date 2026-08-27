# frozen_string_literal: true

module Api
  module V1
    # S3 / BE-700..BE-706 — **tipos de garantia**. Catálogo GLOBAL.
    #
    # **O catálogo que respondia para anônimo.** No legado
    # `ProjectGuaranteeTypesController` declarava `requires_current_user? == false`
    # e o endpoint respondia **sem sessão** (D-23); o gate og/admin/gerente só
    # existia na view. Aqui o módulo nasce dentro de `api/v1/base.rb`, sob o
    # `Api::Root`, que já exige credencial: **401 sem token é o comportamento
    # padrão da base**, não um mecanismo novo.
    #
    # **Sem `current_project!`** (C1, regra 4): o Colaborador precisa LER este
    # catálogo para que o select de garantias do projeto dele suba populado
    # (DEC-18.4), mesmo sem ver a tela de administração.
    class ProjectGuaranteeTypes < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'project_guarantee_types'

      namespace :project_guarantee_types do
        before { authenticate_user! }

        desc 'Lista tipos de garantia' do
          summary 'Tipos de garantia'
          detail 'Catálogo GLOBAL com `R` ao Colaborador (DEC-18.4). Sem credencial → 401 (fecha o D-23).'
        end
        params do
          optional :q, type: String
          optional :active, type: Boolean
          optional :ordering_keys, type: Array[String], desc: 'title | key | sort_order | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(ProjectGuaranteeTypeService, Api::Entities::ProjectGuaranteeType)
        end

        desc 'Detalhe de um tipo de garantia' do
          detail 'Inexistente → 404 (BE-702). No legado dava `MissingTemplate` → 500.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(ProjectGuaranteeTypeService, Api::Entities::ProjectGuaranteeType, params[:id])
        end

        desc 'Cria um tipo de garantia' do
          detail 'BE-703: `user_id` vem da SESSÃO e o do corpo é IGNORADO — este era o único controller do legado ' \
                 'que não o sobrescrevia. Título único. A chave de integração nasce derivada e CONGELADA (DC-22).'
        end
        params do
          requires :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
          optional :is_provisional, type: Boolean, desc: 'DEC-86 — marca o tipo como suposição do seed'
          optional :sort_order, type: Integer
          optional :description, type: String
          optional :observation, type: String
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(ProjectGuaranteeTypeService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::ProjectGuaranteeType, expected: 201)
        end

        desc 'Atualiza um tipo de garantia' do
          detail 'BE-704 / DC-22: renomear o título **não** recalcula a `integration_key`. ' \
                 'A chave só muda se vier explicitamente no corpo.'
        end
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean
          optional :is_provisional, type: Boolean
          optional :sort_order, type: Integer
          optional :description, type: String
          optional :observation, type: String
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(ProjectGuaranteeTypeService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::ProjectGuaranteeType, expected: 200)
        end

        desc 'Remove um tipo de garantia' do
          detail 'Tipo em uso por alguma garantia de projeto → **422 real** (BE-705 / D-24).'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = ProjectGuaranteeTypeService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
