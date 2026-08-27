# frozen_string_literal: true

module Api
  module V1
    # S5 / BE-279 — **tipos de movimentação de risco**. Catálogo GLOBAL.
    #
    # Mesmo gate da tela irmã (`risk_operation_types`) — a assimetria do legado
    # desaparece (FE-279). Sem `current_project!` (C1, regra 4).
    #
    # Duas mudanças visíveis, as duas registradas:
    #
    # - o **filtro por estado** passa a existir. O legado listava
    #   `RiskMovementType.all`, incluindo os desativados, sem marca nem filtro —
    #   enquanto a tela irmã listava só os ativos;
    # - o **`destroy` deixa de mentir**. Lá o ramo de erro respondia `:ok` e a
    #   tela dizia "removido" sem ter removido (D-24).
    class RiskMovementTypes < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'risk_movement_types'

      namespace :risk_movement_types do
        before { authenticate_user! }

        desc 'Lista tipos de movimentação de risco' do
          summary 'Movimentações de risco'
          detail 'Catálogo GLOBAL com `R` ao Colaborador (DEC-18.4).'
          success [code: 200, model: Api::Entities::RiskMovementType]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave de integração'
          optional :active, type: Boolean, desc: 'Só os ativos — filtro que o legado não tinha'
          optional :credit_type, type: String, values: %w[C D], desc: "'C' crédito · 'D' débito"
          optional :is_transfer, type: Boolean
          optional :ordering_keys, type: Array[String], desc: 'title | key | credit_type | system_exclusive | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(Risk::MovementTypeService, Api::Entities::RiskMovementType)
        end

        desc 'Detalhe de um tipo de movimentação'
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(Risk::MovementTypeService, Api::Entities::RiskMovementType, params[:id])
        end

        desc 'Cria um tipo de movimentação' do
          detail "`credit_type` é o SINAL do movimento no saldo: 'D' soma +1, 'C' soma −1. " \
                 'Restrito por check constraint no banco — fora disso o movimento não mexeria no saldo, em silêncio.'
        end
        params do
          requires :title, type: String
          requires :credit_type, type: String, values: %w[C D]
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
          optional :is_system_exclusive, type: Boolean, default: false
          optional :is_transfer, type: Boolean, default: false
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(Risk::MovementTypeService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::RiskMovementType, expected: 201)
        end

        desc 'Atualiza um tipo de movimentação' do
          detail 'Renomear o título NÃO recalcula a chave (DC-22) — e é por ela que os três tipos ' \
                 'funcionais são resolvidos (B-09). No legado a resolução era por título literal.'
        end
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          optional :integration_key, type: String
          optional :credit_type, type: String, values: %w[C D]
          optional :is_active, type: Boolean
          optional :is_system_exclusive, type: Boolean
          optional :is_transfer, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(Risk::MovementTypeService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::RiskMovementType, expected: 200)
        end

        desc 'Remove um tipo de movimentação' do
          detail 'Tipo semeado (`is_default`) ou em uso por movimento → **422 real**, nunca `:ok` (D-24).'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = Risk::MovementTypeService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
