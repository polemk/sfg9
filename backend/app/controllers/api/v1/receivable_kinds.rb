# frozen_string_literal: true

module Api
  module V1
    # S6 / **BE-185** — tipos de recebível. **Catálogo GLOBAL.**
    #
    # **Este endpoint NÃO chama `current_project!`, de propósito** (contrato C1,
    # regra 4).
    #
    # **`#create` passa a responder 422 quando falha.** No legado
    # `receivable_kinds_controller#create` respondia **200** com o registro não
    # gravado: a tela dizia "cadastrado" e nada tinha sido cadastrado.
    class ReceivableKinds < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'receivable_kinds'

      namespace :receivable_kinds do
        before { authenticate_user! }

        desc 'Lista tipos de recebível' do
          summary 'Tipos de recebível'
          detail 'Catálogo GLOBAL. `is_active` NÃO filtra (Q-B12). Chave de ordenação desconhecida é ' \
                 'IGNORADA, não 500 — no legado `nil + " "` derrubava o request.'
          success [code: 200, model: Api::Entities::ReceivableKind]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :active, type: Boolean, desc: 'Só os ativos — filtro EXPLÍCITO, nunca implícito'
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(ReceivableKindService, Api::Entities::ReceivableKind)
        end

        desc 'Detalhe de um tipo de recebível'
        params { requires :id, type: String, desc: 'UUID' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(ReceivableKindService, Api::Entities::ReceivableKind, params[:id])
        end

        desc 'Cria um tipo de recebível' do
          detail 'A chave de integração é derivada do título na CRIAÇÃO e congelada depois (DC-22). ' \
                 'Índice único no título fecha o D-12 (corrida entre duas abas).'
        end
        params do
          requires :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
        end
        post '' do
          authorize!(RESOURCE, :create)
          require_not_readonly!
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(ReceivableKindService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::ReceivableKind, expected: 201)
        end

        desc 'Atualiza um tipo de recebível'
        params do
          requires :id, type: String
          optional :title, type: String
          optional :is_active, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          require_not_readonly!
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(ReceivableKindService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::ReceivableKind, expected: 200)
        end

        desc 'Remove um tipo de recebível' do
          detail 'Bloqueada por borderô vinculado → 422 REAL, com a frase nomeando o vínculo (D-24).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          require_not_readonly!
          result = ReceivableKindService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
