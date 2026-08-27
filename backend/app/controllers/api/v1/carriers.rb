# frozen_string_literal: true

module Api
  module V1
    # S3 / BE-067..BE-071 — **portadores** (contraparte financiadora).
    # Catálogo GLOBAL.
    #
    # **Este endpoint NÃO chama `current_project!`, de propósito** (contrato C1,
    # regra 4 de `§0.6`). O portador é compartilhado entre projetos: é isso que
    # permite ao `risk_control` de um projeto e ao recebível de outro apontarem
    # para a mesma contraparte. Aplicar escopo aqui quebraria os dois.
    #
    # `group_id` chega por parâmetro e **entra no `where`** — id inexistente
    # devolve conjunto **vazio**, nunca a lista inteira. É a forma oposta da do
    # legado, em que a chegada de um id por parâmetro fazia o filtro sumir
    # (família D-01 / D-16 / D-29 / D-76 / D-100).
    class Carriers < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'carriers'

      namespace :carriers do
        before { authenticate_user! }

        desc 'Lista portadores' do
          summary 'Portadores'
          detail 'Catálogo GLOBAL. Busca SIMÉTRICA (mesmo conjunto com e sem ordenação) e paginação REAL (D-20).'
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :group_id, type: String, desc: 'Filtra por grupo. Id inexistente devolve vazio.'
          optional :financial_agent, type: String, values: ::Carrier::FINANCIAL_AGENTS
          optional :uf, type: String
          optional :active, type: Boolean
          optional :ordering_keys, type: Array[String],
                                   desc: 'title | key | bank_code | financial_agent | city | uf | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(CarrierService, Api::Entities::Carrier)
        end

        desc 'Detalhe de um portador' do
          detail 'DC-08 / D-22: no legado o HTML e o SCSS do detalhe existem e NENHUMA rota chega neles.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(CarrierService, Api::Entities::Carrier, params[:id])
        end

        desc 'Cria um portador' do
          detail '`bank_code` é STRING e preserva `001` (DC-12). ' \
                 '`subordinated_accounts_percent` NÃO é aceito: é derivado no servidor (DC-09).'
        end
        params do
          requires :title, type: String
          optional :resume, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
          optional :bank_code, type: String, desc: 'Código COMPE. String — `001` continua `001`.'
          optional :senior_accounts, type: Integer
          optional :subordinated_accounts, type: Integer
          optional :net_worth, type: BigDecimal
          optional :group_id, type: String
          optional :financial_agent, type: String, values: ::Carrier::FINANCIAL_AGENTS
          optional :city, type: String
          optional :uf, type: String
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(CarrierService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::Carrier, expected: 201)
        end

        desc 'Atualiza um portador'
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          optional :resume, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean
          optional :bank_code, type: String
          optional :senior_accounts, type: Integer
          optional :subordinated_accounts, type: Integer
          optional :net_worth, type: BigDecimal
          optional :group_id, type: String
          optional :financial_agent, type: String, values: ::Carrier::FINANCIAL_AGENTS
          optional :city, type: String
          optional :uf, type: String
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(CarrierService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::Carrier, expected: 200)
        end

        desc 'Remove um portador' do
          detail 'BLOQUEIA com 422 quando há conexão de projeto, limite de risco ou recebível. ' \
                 'NUNCA cascateia — no legado excluir um portador APAGAVA os `risk_controls` dele (D-24).'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = CarrierService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end

        # --- Logo (DEC-47 / DEC-91) -----------------------------------------
        # ActiveStorage no PRÓPRIO model. Não é `Medium` (a tabela `media` não
        # tem dono nem escopo) e não é Paperclip (não portado). O tipo REAL do
        # arquivo é verificado — o legado tinha a detecção de spoof desligada.
        desc 'Envia o logo do portador' do
          detail 'DEC-47. Tipo REAL do arquivo verificado (OPS-051): `.exe` renomeado para `.png` é recusado.'
        end
        params do
          requires :id, type: String, desc: 'UUID do registro'
          requires :file, type: File
        end
        post ':id/logo' do
          authorize!(RESOURCE, :update)
          render_catalog_write(CarrierService.attach_logo(id: params[:id], file: params[:file]),
                               Api::Entities::Carrier, expected: 200)
        end

        desc 'Remove o logo do portador'
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id/logo' do
          authorize!(RESOURCE, :update)
          render_catalog_write(CarrierService.remove_logo(id: params[:id]),
                               Api::Entities::Carrier, expected: 200)
        end
      end
    end
  end
end
