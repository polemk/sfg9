# frozen_string_literal: true

module Api
  module V1
    # S6 / **BE-185** — carteiras. **Catálogo GLOBAL.**
    #
    # **Este endpoint NÃO chama `current_project!`, de propósito** (contrato C1,
    # regra 4). Uma carteira cadastrada "no projeto A" sumiria do projeto B e
    # quebraria os borderôs que já apontam para ela.
    #
    # Leitura: qualquer autenticado, inclusive Colaborador (DEC-18.4).
    # Escrita: OG/Admin/Gerente, decidido pela matriz **no servidor**.
    class Wallets < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'wallets'

      namespace :wallets do
        before { authenticate_user! }

        desc 'Lista carteiras' do
          summary 'Carteiras'
          detail 'Catálogo GLOBAL. `is_active` NÃO filtra (Q-B12): carteira desativada continua no select ' \
                 'do borderô, como no legado. Chave de ordenação desconhecida é IGNORADA, não 500.'
          success [code: 200, model: Api::Entities::Wallet]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :active, type: Boolean, desc: 'Só as ativas — filtro EXPLÍCITO, nunca implícito'
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(WalletService, Api::Entities::Wallet)
        end

        desc 'Detalhe de uma carteira'
        params { requires :id, type: String, desc: 'UUID' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(WalletService, Api::Entities::Wallet, params[:id])
        end

        desc 'Cria uma carteira' do
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
          render_catalog_write(WalletService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::Wallet, expected: 201)
        end

        desc 'Atualiza uma carteira'
        params do
          requires :id, type: String
          optional :title, type: String
          optional :is_active, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          require_not_readonly!
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(WalletService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::Wallet, expected: 200)
        end

        desc 'Remove uma carteira' do
          detail 'Bloqueada por borderô vinculado → 422 REAL, com a frase nomeando o vínculo (D-24).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          require_not_readonly!
          result = WalletService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
