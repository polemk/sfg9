# frozen_string_literal: true

module Api
  module V1
    # S4 / BE-102..BE-105 — **conexões projeto ↔ portador**.
    #
    # **Não existe `constantize` de parâmetro aqui.** O legado montava a ação
    # inteira a partir de `params[:owner_type].constantize` e
    # `params[:connection_type].constantize`: qualquer classe da aplicação podia
    # ser instanciada e enumerada a partir da query string. O sentido da conexão
    # é fixo — projeto corrente ↔ portador do catálogo global — e o projeto vem
    # de `current_project!`, nunca do parâmetro.
    #
    # O lote devolve resultado **por item** e aplica o que dá para aplicar. No
    # legado só o último item era inspecionado por erro, e um lote vazio
    # derrubava a ação com `NoMethodError`.
    class ProjectCarrierConnections < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'project_to_carrier_connections'

      namespace :project_carrier_connections do
        before { authenticate_user! }

        desc 'Portadores conectados ao projeto corrente' do
          summary 'Conexões do projeto'
          success [code: 200, model: Api::Entities::ProjectCarrierConnection]
          is_array true
        end
        params do
          optional :carrier_id, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = ProjectCarrierConnectionService.index(project: project, params: params)[:data]
          Api::Entities::ProjectCarrierConnection.represent(paginate(scope).to_a)
        end

        desc 'Candidatos a conexão' do
          detail 'BE-104 — **um** endpoint. O legado tinha dois quase idênticos (`search`, limite 25, e ' \
                 '`connections`, limite 200), e o segundo listava o catálogo inteiro sem filtro nenhum. ' \
                 'O estado "conectado" sai resolvido em UMA consulta, não em `include?` por linha.'
        end
        params do
          optional :q, type: String
          optional :group_id, type: String
          optional :active, type: Boolean
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 25
        end
        get 'candidates' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = ProjectCarrierConnectionService.candidates(project: project, params: params)
          Api::Entities::CarrierCandidate.represent(
            paginate(result[:data][:scope]).to_a,
            connected_ids: result[:data][:connected_ids]
          )
        end

        desc 'Conecta ou desconecta portadores em LOTE' do
          detail 'Lote vazio → **400**. Resultado **por item**. Desconectar o que não está conectado NÃO ' \
                 'dá 500: responde "não estava conectado". Conectar o que já está é sucesso, não erro.'
          failure [{ code: 400, message: 'Lote vazio ou ação inválida' }]
        end
        params do
          requires :action_kind, type: String, values: ProjectCarrierConnectionService::ACTIONS,
                                 desc: 'connect | disconnect — conjunto FECHADO, nunca `constantize`'
          requires :carrier_ids, type: Array[String], desc: 'UUIDs de portadores'
        end
        put 'batch' do
          authorize!(RESOURCE, :update)
          project = current_project!

          process_service_response(
            ProjectCarrierConnectionService.update_connections(
              project: project, action: params[:action_kind], carrier_ids: params[:carrier_ids]
            )
          )
        end

        desc 'Remove UMA conexão pelo id dela' do
          detail 'No legado esta action nunca funcionou: o `before_action` preenchia `@connections` ' \
                 '(plural) e a action lia `@connection` (singular) — `NoMethodError` garantido (BE-105).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          process_service_response(ProjectCarrierConnectionService.destroy(project: project, id: params[:id]))
        end
      end
    end
  end
end
