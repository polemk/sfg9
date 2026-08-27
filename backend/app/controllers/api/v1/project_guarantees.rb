# frozen_string_literal: true

module Api
  module V1
    # S4 / BE-118, BE-119 — **garantias do projeto**.
    #
    # É o endpoint do defeito que dá nome ao contrato **C1**. No legado
    # (`pub/project_guarantees_controller.rb:21-22`):
    #
    #     @project_guarantees = ProjectGuarantee.joins(...).where(project_id: current_user.default_project_id)
    #     @project_guarantees = ProjectGuarantee.where(id: params[:project_guarantee_id]) unless ...
    #
    # A segunda linha **reatribui** a relação e o filtro de projeto desaparece.
    # Aqui `project_guarantee_id` entra no `where` DENTRO do escopo, e id de
    # outro projeto devolve **vazio** — nunca 403, que confirmaria a existência
    # do registro alheio.
    class ProjectGuarantees < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'project_guarantees'

      namespace :project_guarantees do
        before { authenticate_user! }

        desc 'Lista as garantias do projeto corrente' do
          summary 'Garantias do projeto'
          detail 'Ordenar por "Título" FUNCIONA (D-32): o legado mandava `risk_operations.title`, tabela ' \
                 'fora do join, e o SQL falhava. Paginação real — o limite default do legado era 1000.'
          success [code: 200, model: Api::Entities::ProjectGuarantee]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca no título da garantia OU no do portador'
          optional :project_guarantee_id, type: String, desc: 'Filtro por id — DENTRO do escopo (D-29)'
          optional :carrier_id, type: String
          optional :guarantee_type_id, type: String
          optional :order_mode, type: String, values: %w[dash]
          optional :ordering_keys, type: Array[String], desc: 'title | guarantee_type | carrier | value | created_at'
          optional :ordering_style, type: Array[String]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = ProjectGuaranteeService.index(project: project, params: params)[:data]
          Api::Entities::ProjectGuarantee.represent(paginate(scope).to_a)
        end

        desc 'Portadores que podem dar garantia neste projeto' do
          detail 'BE-119 — **um único critério**: o portador está CONECTADO ao projeto. O legado usava ' \
                 '`active_risk_controls_carriers` no botão e `project.carriers` no formulário: a tela ' \
                 'oferecia portador que o servidor recusava.'
        end
        get 'available_carriers' do
          authorize!(RESOURCE, :read)
          project = current_project!

          Api::Entities::CarrierCandidate.represent(
            ProjectGuaranteeService.available_carriers(project),
            connected_ids: Set.new(ProjectToCarrierConnection.for_project(project).pluck(:carrier_id))
          )
        end

        desc 'Detalhe de uma garantia'
        params { requires :id, type: String }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = ProjectGuaranteeService.show(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::ProjectGuarantee.represent(result[:data])
        end

        desc 'Cria uma garantia' do
          detail 'O autor vem da SESSÃO; `user_id` e `project_id` do corpo não são declarados. Portador ' \
                 'não conectado ao projeto → 422.'
        end
        params do
          requires :title, type: String
          requires :carrier_id, type: String
          requires :guarantee_type_id, type: String
          requires :value, type: BigDecimal
          optional :observation, type: String
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          result = ProjectGuaranteeService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::ProjectGuarantee.represent(result[:data])
        end

        desc 'Atualiza uma garantia' do
          detail 'No legado o `update` não sobrescrevia `user_id` NEM `project_id`: era troca de dono e de ' \
                 'tenant por campo escondido de formulário.'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :carrier_id, type: String
          optional :guarantee_type_id, type: String
          optional :value, type: BigDecimal
          optional :observation, type: String
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = ProjectGuaranteeService.update(project: project, id: params[:id], attrs: attrs,
                                                  actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::ProjectGuarantee.represent(result[:data])
        end

        desc 'Remove uma garantia' do
          detail 'O legado respondia `:ok` em qualquer caso (`errors.any? ? :ok : :ok`).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          result = ProjectGuaranteeService.destroy(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
