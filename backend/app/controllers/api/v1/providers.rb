# frozen_string_literal: true

module Api
  module V1
    # S4 / BE-059..BE-063, BE-065 — **fornecedores**, escopados por projeto.
    #
    # **Sem projeto corrente é 404, não o catálogo geral.** O legado aplicava o
    # escopo com `unless current_user.default_project_id.blank?`: sessão sem
    # projeto padrão recebia **todos os fornecedores de todos os projetos**.
    #
    # O autopreenchimento por CNPJ vive em `GET /api/v1/cnpj/:cnpj`
    # (`Api::V1::CnpjLookup`, DEC-46): a integração é a mesma para fornecedor,
    # empresa e portador, e um endpoint por tela seria escrevê-la três vezes.
    class Providers < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'providers'

      helpers do
        def provider_usage_counts(registros)
          BlockingDependents.counts_by_dependent(Provider, Array(registros).map(&:id))
        end

        def provider_attrs
          declared(params, include_missing: false).symbolize_keys.except(:id, :page, :per_page)
        end
      end

      namespace :providers do
        before { authenticate_user! }

        desc 'Lista os fornecedores do projeto corrente' do
          summary 'Fornecedores'
          detail 'Escopo OBRIGATÓRIO. Paginação e ordenação aplicadas JUNTAS (no legado a ordenação ' \
                 'personalizada e a paginação viviam em ramos diferentes e só uma valia).'
          success [code: 200, model: Api::Entities::Provider]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título, chave ou documento'
          optional :provider_id, type: String, desc: 'Filtro por id — DENTRO do escopo'
          optional :active, type: Boolean
          optional :ordering_keys, type: Array[String], desc: 'title | key | document | created_at'
          optional :ordering_style, type: Array[String]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = ProviderService.index(project: project, params: params)[:data]
          if params[:provider_id].present?
            scope = ProviderService.uuid?(params[:provider_id]) ? scope.where(id: params[:provider_id]) : scope.none
          end

          registros = paginate(scope).to_a
          Api::Entities::Provider.represent(registros, usage: provider_usage_counts(registros))
        end

        desc 'Detalhe de um fornecedor' do
          detail 'A tela de detalhe passa a existir (D-22/DC-08). Id de outro projeto → 404.'
        end
        params { requires :id, type: String }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = ProviderService.show(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Provider.represent(result[:data], usage: provider_usage_counts([result[:data]]))
        end

        desc 'Cria um fornecedor' do
          detail 'O `project_id` vem do servidor. O documento é o par (tipo, número) e continua OPCIONAL (DC-11); ' \
                 'quando existe, é validado com dígito verificador.'
        end
        params do
          requires :title, type: String
          optional :resume, type: String
          optional :is_active, type: Boolean, default: true
          optional :document_type, type: String, values: Sfg::Document::TYPES
          optional :document, type: String
          optional :legal_name, type: String
          optional :trade_name, type: String
          optional :status, type: String
          optional :opened_at, type: Date
          optional :status_changed_at, type: Date
          optional :email, type: String
          optional :phone, type: String
          optional :zip_code, type: String
          optional :street, type: String
          optional :number, type: String
          optional :complement, type: String
          optional :district, type: String
          optional :city, type: String
          optional :state, type: String
          optional :activities, type: Hash
          optional :cnpj_fetched_at, type: DateTime
          # `logo` NÃO é declarado aqui: o anexo tem rota própria
          # (`POST :id/logo`). Dois caminhos para o mesmo arquivo são duas
          # regras de validação de anexo, e uma delas fica para trás.
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          result = ProviderService.create(project: project, attrs: provider_attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::Provider.represent(result[:data])
        end

        desc 'Atualiza um fornecedor' do
          detail '`title` e `integration_key` continuam obrigatórios TAMBÉM aqui (BE-062). ' \
                 '`project_id` é ignorado — o campo escondido de formulário do legado movia o fornecedor de projeto (D-23).'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :resume, type: String
          optional :integration_key, type: String
          optional :is_active, type: Boolean
          optional :document_type, type: String, values: Sfg::Document::TYPES
          optional :document, type: String
          optional :legal_name, type: String
          optional :trade_name, type: String
          optional :status, type: String
          optional :opened_at, type: Date
          optional :status_changed_at, type: Date
          optional :email, type: String
          optional :phone, type: String
          optional :zip_code, type: String
          optional :street, type: String
          optional :number, type: String
          optional :complement, type: String
          optional :district, type: String
          optional :city, type: String
          optional :state, type: String
          optional :activities, type: Hash
          optional :cnpj_fetched_at, type: DateTime
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          result = ProviderService.update(project: project, id: params[:id], attrs: provider_attrs,
                                          actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Provider.represent(result[:data])
        end

        # --- Logo (DEC-91) ---------------------------------------------------
        # ActiveStorage no PRÓPRIO model, no mesmo caminho do portador. Não é
        # `Medium` e não é Paperclip: as 4 colunas `logo_*` do legado não foram
        # recriadas, e a string literal `"missing.jpg"` deixou de significar
        # "sem arquivo".
        desc 'Envia o logo do fornecedor' do
          detail 'Tipo REAL do arquivo verificado (magic bytes): `.exe` renomeado para `.png` é recusado. ' \
                 'Limite de 1 MB, o mesmo do legado, agora conferido NO SERVIDOR.'
        end
        params do
          requires :id, type: String
          requires :file, type: File
        end
        post ':id/logo' do
          authorize!(RESOURCE, :update)
          project = current_project!

          result = ProviderService.attach_logo_file(project: project, id: params[:id], file: params[:file])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          # `POST` no Grape responde 201 por default. Aqui NÃO nasce recurso
          # novo: o registro é o mesmo, com um anexo a mais.
          status 200
          Api::Entities::Provider.represent(result[:data])
        end

        desc 'Remove o logo do fornecedor'
        params { requires :id, type: String }
        delete ':id/logo' do
          authorize!(RESOURCE, :update)
          project = current_project!

          result = ProviderService.remove_logo(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Provider.represent(result[:data])
        end

        desc 'Remove um fornecedor' do
          detail 'Renegociação vinculada bloqueia com **422 real** (a checagem completa entra com a S9).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          result = ProviderService.destroy(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
