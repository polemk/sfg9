# frozen_string_literal: true

module Api
  module V1
    # S4 / BE-050..BE-057 — **empresas**, o primeiro consumidor do contrato C1.
    #
    # **Toda ação declara o escopo numa linha visível**: `project = current_project!`.
    # Um endpoint desta fatia sem essa linha é um vazamento de tenant esperando
    # acontecer — é o portão 9.6 do `tasks.md`.
    #
    # O `project_id` que vier no CORPO é **sempre ignorado**: ele nem é declarado
    # no `params do`. É a ausência que fecha a família D-01/D-16/D-29.
    class Companies < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'companies'

      helpers do
        # Contagem POR DEPENDENTE, uma consulta por tipo, para a PÁGINA inteira.
        # Vale zero enquanto a fatia dona não entregou a tabela.
        def usage_counts(registros)
          BlockingDependents.counts_by_dependent(Company, Array(registros).map(&:id))
        end
      end

      namespace :companies do
        before { authenticate_user! }

        desc 'Lista as empresas do projeto corrente' do
          summary 'Empresas'
          detail 'Escopo por `current_project!`. Paginação e ordenação APLICADAS (D-20): no legado ' \
                 '`.order/.limit/.offset` eram descartados por `where!` e a UI de paginação era decorativa.'
          success [code: 200, model: Api::Entities::Company]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por razão social (ILIKE com bind)'
          optional :company_id, type: String, desc: 'Filtro por id — aplicado DENTRO do escopo (D-29)'
          optional :order_mode, type: String, values: %w[dash], desc: 'Resumo da tela inicial'
          optional :ordering_keys, type: Array[String], desc: 'title | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
          # `project_id` NÃO é declarado, de propósito.
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = CompanyService.index(project: project, params: params)
          scope = result[:data]
          # Filtro por id: DENTRO do escopo. Id malformado ou de outro projeto
          # devolve VAZIO, nunca a lista inteira e nunca 403 (não se confirma a
          # existência de registro alheio).
          if params[:company_id].present?
            scope = CompanyService.uuid?(params[:company_id]) ? scope.where(id: params[:company_id]) : scope.none
          end

          registros = paginate(scope).to_a
          Api::Entities::Company.represent(
            registros,
            usage: usage_counts(registros),
            carriers_count: ProjectToCarrierConnection.for_project(project).count
          )
        end

        desc 'Resumo de limites de risco da empresa' do
          detail '⏳ BLOQUEADO pela S5 (`risk_controls`). Enquanto a tabela não existe devolve o resumo ' \
                 'vazio — a MESMA forma, com zeros —, nunca 500. Data inválida responde 400 pelo Grape.'
        end
        params do
          optional :company_id, type: String, desc: 'Vazio = resumo do projeto inteiro'
          optional :date, type: Date, default: -> { Date.current }
        end
        get 'risk_summary/list' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = CompanyService.risk_summary(project: project, id: params[:company_id], date: params[:date])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end

        desc 'Detalhe de uma empresa' do
          detail 'Id de OUTRO projeto responde 404, igual a id inexistente. ' \
                 'O legado respondia `MissingTemplate` → 500 (BE-057).'
        end
        params { requires :id, type: String, desc: 'UUID da empresa' }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = CompanyService.show(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          Api::Entities::Company.represent(
            result[:data],
            usage: usage_counts([result[:data]]),
            carriers_count: ProjectToCarrierConnection.for_project(project).count
          )
        end

        desc 'Cria uma empresa' do
          detail 'O `project_id` do corpo é ignorado — ele nem é declarado. `:id` idem (mass assignment de PK).'
        end
        params do
          requires :title, type: String, desc: 'Razão social. Única POR PROJETO'
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          result = CompanyService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::Company.represent(result[:data])
        end

        desc 'Atualiza uma empresa' do
          detail 'DC-04 — mover empresa entre projetos NÃO é caso de uso: arrastaria limites, recebíveis ' \
                 'e renegociações para outro tenant. O `project_id` do corpo é ignorado TAMBÉM aqui (D-23).'
        end
        params do
          requires :id, type: String
          optional :title, type: String
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = CompanyService.update(project: project, id: params[:id], attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          Api::Entities::Company.represent(result[:data])
        end

        desc 'Remove uma empresa' do
          detail 'Bloqueio por dependente responde **422 REAL**. O legado respondia `:ok` mesmo sem excluir ' \
                 '(`errors.any? ? :ok : :ok`) e a tela dizia "removido com sucesso" (D-24).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          result = CompanyService.destroy(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end


    end
  end
end
