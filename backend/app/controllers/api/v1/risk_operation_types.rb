# frozen_string_literal: true

module Api
  module V1
    # S5 / BE-278 — **tipos de limite**. Catálogo GLOBAL.
    #
    # **Sem `current_project!`** (C1, regra 4): um tipo de limite vale para todos
    # os projetos, e o Colaborador precisa LER o catálogo para que o select do
    # formulário de limite suba populado (DEC-18.4) mesmo sem ver a tela de
    # administração.
    #
    # **FE-279 — a assimetria das duas telas de tipos desaparece.** No legado o
    # gate de papel de "Tipos de Limite" e o de "Movimentações de Risco" eram
    # diferentes, e nos dois casos ele existia **só na view**: qualquer
    # requisição fora da tela fazia tudo (D-23/D-34). Aqui os dois endpoints
    # passam pela mesma linha da `Authorization::Matrix`.
    class RiskOperationTypes < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'risk_operation_types'

      namespace :risk_operation_types do
        before { authenticate_user! }

        desc 'Lista tipos de limite' do
          summary 'Tipos de limite'
          detail 'Catálogo GLOBAL com `R` ao Colaborador (DEC-18.4). Sem credencial → 401.'
          success [code: 200, model: Api::Entities::RiskOperationType]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave de integração'
          optional :active, type: Boolean, desc: 'Só os ativos'
          optional :has_pre, type: Boolean, desc: 'Só os que usam pré-faturamento'
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(Risk::OperationTypeService, Api::Entities::RiskOperationType)
        end

        desc 'Detalhe de um tipo de limite' do
          detail 'Inexistente → 404. No legado o `show` renderizava template inexistente → 500.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(Risk::OperationTypeService, Api::Entities::RiskOperationType, params[:id])
        end

        desc 'Cria um tipo de limite' do
          detail 'O tipo GERA os próprios subtipos (1 ou 2, conforme `has_pre_faturamento`). ' \
                 '`user_id` vem da SESSÃO. A chave de integração nasce derivada e CONGELADA (DC-22).'
        end
        params do
          requires :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean, default: true
          optional :allow_manual_operations, type: Boolean, default: true
          optional :allow_receivable_entries, type: Boolean, default: true
          optional :has_pre_faturamento, type: Boolean, default: false,
                                         desc: 'Só na criação — depois é imutável.'
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(Risk::OperationTypeService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::RiskOperationType, expected: 201)
        end

        desc 'Atualiza um tipo de limite' do
          detail '**`has_pre_faturamento` não é aceita aqui**: mudá-la deixaria o tipo com o número errado ' \
                 'de subtipos e trocaria em silêncio o bucket de limite de toda operação já gravada. ' \
                 'No legado ela está no `permit`. Renomear o título NÃO recalcula a chave (DC-22).'
        end
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean
          optional :allow_manual_operations, type: Boolean
          optional :allow_receivable_entries, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(Risk::OperationTypeService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::RiskOperationType, expected: 200)
        end

        desc 'Remove um tipo de limite' do
          detail 'Tipo semeado (`is_default`) ou em uso por limite/operação → **422 real** (D-24).'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = Risk::OperationTypeService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
