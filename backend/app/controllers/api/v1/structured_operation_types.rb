# frozen_string_literal: true

module Api
  module V1
    # S8 / **BE-296**…**BE-299**, **FE-309** — tipos de operação estruturada.
    #
    # **Catálogo GLOBAL**: não chama `current_project!` (C1, regra 4). O
    # Colaborador **lê** (DEC-18.4), para que o select do formulário de operação
    # suba populado mesmo sem ele ver a tela de administração.
    #
    # ## FE-309 — a correção de segurança desta unidade
    #
    # Os controllers dedicados do legado herdam `requires_current_user? == false`:
    # `search`, `create`, `update` e `destroy` **não exigem login pelo
    # `before_action`**. Funcionavam só porque `current_user` precisava existir
    # para `current_user.default_project_id` não quebrar — o que é acidente, não
    # autorização. Aqui todo endpoint exige JWT válido **e** passa pela
    # `Authorization::Matrix`.
    class StructuredOperationTypes < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'structured_operation_types'

      namespace :structured_operation_types do
        before { authenticate_user! }

        desc 'Lista tipos de operação estruturada' do
          summary 'Tipos de operação estruturada'
          detail 'Catálogo GLOBAL com `R` ao Colaborador (DEC-18.4). **`active` é OPCIONAL** — no legado a ' \
                 'lista era sempre `.active`, e tipo desativado sumia da administração sem como reativar.'
          success [code: 200, model: Api::Entities::StructuredOperationType]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :active, type: Boolean, desc: 'Só os ativos. Ausente = todos.'
          optional :ordering_keys, type: Array[String],
                                   values: ::StructuredOperationType::ORDERING.allowed.keys,
                                   desc: 'title | key | created_at — chave fora da lista responde 400'
          optional :ordering_style, type: Array[String], values: %w[up down asc desc ascending descending]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          render_catalog_page(Structured::OperationTypeService, Api::Entities::StructuredOperationType)
        end

        desc 'Detalhe de um tipo' do
          detail 'Inexistente ou id malformado → **404**. No legado o `show` renderizava template inexistente → 500.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          render_catalog_record(Structured::OperationTypeService, Api::Entities::StructuredOperationType, params[:id])
        end

        desc 'Cria um tipo' do
          detail '`title` obrigatório e único; `integration_key` derivada do título **só no create** e ÚNICA no ' \
                 'banco — no legado dois títulos diferentes derivavam a mesma chave e colidiam em silêncio. ' \
                 '`user_id` vem da SESSÃO.'
        end
        params do
          requires :title, type: String
          optional :integration_key, type: String, desc: 'Derivada do título quando ausente. Congelada depois.'
          optional :is_active, type: Boolean, default: true
          optional :allow_manual_operations, type: Boolean, default: true
          optional :allow_receivable_entries, type: Boolean, default: false
          optional :has_pre_faturamento, type: Boolean, default: false,
                                         desc: 'Sem consumidor (Q-R15). Coluna migrada, não regra.'
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(Structured::OperationTypeService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::StructuredOperationType, expected: 201)
        end

        desc 'Atualiza um tipo' do
          detail 'BE-298 — **`title` e `integration_key` são recusados aqui.** A UI já os mostra como readonly; ' \
                 'agora vale no servidor. Alterar a chave a qualquer momento quebra integrações.'
        end
        params do
          requires :id, type: String, desc: 'UUID do registro'
          # Os dois são DECLARADOS de propósito, para serem **recusados com
          # mensagem**. Deixá-los fora do `params` faria o Grape descartá-los em
          # silêncio: o cliente mandaria um título novo, receberia 200 e o
          # título não teria mudado — que é pior do que recusar, porque parece
          # ter funcionado.
          optional :title, type: String, desc: 'IMUTÁVEL — enviar responde 422 com o motivo'
          optional :integration_key, type: String, desc: 'IMUTÁVEL — é contrato de integração'
          optional :is_active, type: Boolean
          optional :allow_manual_operations, type: Boolean
          optional :allow_receivable_entries, type: Boolean
          optional :has_pre_faturamento, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(
            Structured::OperationTypeService.update(id: params[:id], attrs: attrs, actor: acting_user),
            Api::Entities::StructuredOperationType, expected: 200
          )
        end

        desc 'Remove um tipo' do
          detail 'BE-299 — tipo semeado (`is_default`) ou em uso por operação → **422 REAL** com a frase dizendo ' \
                 'por quê. No legado o ternário `errors.any? ? :ok : :ok` respondia 200 e a tela recarregava a ' \
                 'lista com o registro ainda lá. **Os 4 tipos semeados são todos `is_default`.**'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = Structured::OperationTypeService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
