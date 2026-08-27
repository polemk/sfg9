# frozen_string_literal: true

module Api
  module V1
    # S4 / BE-080..BE-096, BE-100, BE-101 — **o CRUD do projeto**.
    #
    # **Este endpoint NÃO chama `current_project!`, e isso não é esquecimento.**
    # `current_project!` responde "qual é o projeto corrente"; aqui a pergunta é
    # "quais projetos existem para este usuário", e a resposta é
    # `Project.visible_to(user)` — que é OUTRO escopo, com regra própria
    # (DEC-99: OG e Admin enxergam todos, sem participação). Escopar a lista de
    # projetos pelo projeto corrente seria circular.
    #
    # **D-29 fechado:** no legado `Project.where(id: params[:project_id])`
    # **substituía** a lista escopada por participação — qualquer autenticado
    # lia qualquer projeto por id.
    class Projects < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'projects'

      helpers do
        def project_attrs
          declared(params, include_missing: false)
            .symbolize_keys
            .except(:id, :page, :per_page, :responsible_mode,
                    :responsible_user_id, :responsible_name, :responsible_email)
        end

        def responsible_payload
          {
            user_id: params[:responsible_user_id],
            name: params[:responsible_name],
            email: params[:responsible_email]
          }
        end

        def members_counts(registros)
          ids = Array(registros).map(&:id)
          return {} if ids.empty?

          Membership.where(project_id: ids).group(:project_id).count
        end
      end

      namespace :projects do
        before { authenticate_user! }

        desc 'Lista os projetos visíveis ao usuário' do
          summary 'Projetos'
          detail 'Escopo = `Project.visible_to` (DEC-99). `project_id` e `importing_id` são aplicados ' \
                 'DENTRO do escopo — no legado eles o SUBSTITUÍAM (D-29).'
          success [code: 200, model: Api::Entities::Project]
          is_array true
        end
        params do
          optional :q, type: String
          optional :project_id, type: String, desc: 'Filtro por id — DENTRO do escopo'
          optional :importing_id, type: Integer, desc: 'Lote de importação do legado'
          optional :order_mode, type: String, values: %w[dash]
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at | updated_at'
          optional :ordering_style, type: Array[String]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)

          scope = ProjectService.index(user: current_user, params: params)[:data]
          registros = paginate(scope.includes(:segment, :sub_segment, :owner, :responsible)).to_a
          Api::Entities::Project.represent(registros, members_counts: members_counts(registros))
        end

        desc 'Autocomplete de projetos' do
          detail 'BE-083 — `ILIKE` (o legado usava `LIKE` cru, case-sensitive no Postgres: digitar em ' \
                 'minúscula não achava nada) e **com limite**.'
        end
        params do
          optional :q, type: String
          optional :limit, type: Integer, default: 10
        end
        get 'autocomplete' do
          authorize!(RESOURCE, :read)

          result = ProjectService.autocomplete(user: current_user, term: params[:q], limit: params[:limit])
          Api::Entities::ProjectOption.represent(result[:data])
        end

        desc 'Candidatos a responsável' do
          detail 'BE-084 — filtrados por hierarquia de papel (`Authorization::Hierarchy`), no SERVIDOR. ' \
                 'No legado a filtragem era um decorator de view: a rota aceitava qualquer id.'
        end
        params do
          optional :q, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get 'responsible_candidates' do
          authorize!(RESOURCE, :read)

          result = ProjectService.responsible_candidates(actor: acting_user, params: params)
          paginate(result[:data]).map { |u| { id: u.id, name: u.name, email: u.email } }
        end

        desc 'Detalhe de um projeto' do
          detail 'Projeto inexistente e projeto sem acesso respondem o MESMO status (404).'
        end
        params { requires :id, type: String }
        get ':id' do
          authorize!(RESOURCE, :read)

          result = ProjectService.show(user: current_user, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Project.represent(result[:data])
        end

        desc 'Cria um projeto' do
          detail '**D-38 fechado:** com responsável novo, a pessoa recebe um LINK para definir a própria ' \
                 'credencial (`Auth::InviteService`). Nenhuma senha é montada, exibida ou enviada — o ' \
                 'legado montava `username` e senha em texto plano num hash para a view. ' \
                 '**DC-14:** indicando um responsável existente, o CRIADOR permanece com participação.'
          failure [{ code: 422, message: 'Responsável em branco no modo `existing` — 422, não o 500 do legado' }]
        end
        params do
          requires :name, type: String, desc: 'Nome do projeto. Único. O slug é derivado dele e IMUTÁVEL (DC-17)'
          optional :is_active, type: Boolean, default: true
          optional :segment_id, type: String
          optional :sub_segment_id, type: String
          optional :color, type: String
          optional :address_type, type: String
          optional :address, type: String
          optional :address_number, type: String
          optional :address_complement, type: String
          optional :neighborhood, type: String
          optional :cep, type: String
          optional :address_state, type: String
          optional :address_city, type: String
          optional :closing_date, type: Date
          optional :has_safegold_management, type: Boolean
          optional :availability_note, type: String, desc: 'HTML do ActionText'
          optional :responsible_mode, type: String, values: %w[new existing none], default: 'none'
          optional :responsible_user_id, type: String
          optional :responsible_name, type: String
          optional :responsible_email, type: String
          # `avatar` NÃO é declarado: o anexo tem rota própria (`POST :id/logo`).
          # `slug`, `integration_key`, `is_sandbox`, `has_bi` e `importing_id`
          # NÃO são declarados: os dois primeiros são derivados e congelados, os
          # três últimos não têm caminho de escrita pela tela (nem no legado).
        end
        post '' do
          authorize!(RESOURCE, :create)

          result = ProjectService.create(actor: acting_user, attrs: project_attrs,
                                         responsible_mode: params[:responsible_mode],
                                         responsible: responsible_payload)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::Project.represent(result[:data])
        end

        desc 'Atualiza um projeto' do
          detail 'O `slug` NÃO muda ao renomear (DC-17): no legado `set_smart_id` rodava em todo ' \
                 '`before_validation` e renomear o projeto quebrava todas as URLs baseadas nele. ' \
                 'A marca de BI tem endpoint próprio e não muda por aqui (DC-16).'
        end
        params do
          requires :id, type: String
          optional :name, type: String
          optional :is_active, type: Boolean
          optional :segment_id, type: String
          optional :sub_segment_id, type: String
          optional :color, type: String
          optional :address_type, type: String
          optional :address, type: String
          optional :address_number, type: String
          optional :address_complement, type: String
          optional :neighborhood, type: String
          optional :cep, type: String
          optional :address_state, type: String
          optional :address_city, type: String
          optional :closing_date, type: Date
          optional :availability_note, type: String
          optional :responsible_user_id, type: String
        end
        put ':id' do
          authorize!(RESOURCE, :update)

          responsavel = params.key?('responsible_user_id') ? { user_id: params[:responsible_user_id] } : nil
          result = ProjectService.update(actor: acting_user, user: current_user, id: params[:id],
                                         attrs: project_attrs, responsible: responsavel)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Project.represent(result[:data])
        end

        desc 'Marca "Gerido pela Safegold"' do
          detail 'BE-093. ⚠ A cópia da marca nas 6 tabelas filhas depende da **Q-02** e NÃO foi criada: ' \
                 'no legado ela era re-carimbada por `update_all` só em `companies`, e qualquer relatório ' \
                 'que filtrasse por ela mentia (D-30/DC-01). `Company` lê a marca DERIVADA do projeto.'
        end
        params do
          requires :id, type: String
          requires :value, type: Boolean
        end
        patch ':id/safegold_management' do
          authorize!(RESOURCE, :update)

          result = ProjectService.set_safegold_management(user: current_user, id: params[:id],
                                                          value: params[:value])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Project.represent(result[:data])
        end

        desc 'Marca "BI contratado"' do
          detail 'DC-16 — marca comercial, gravada e exibida como hoje: pode haver consumidor externo.'
        end
        params do
          requires :id, type: String
          requires :value, type: Boolean
        end
        patch ':id/bi' do
          authorize!(RESOURCE, :update)

          result = ProjectService.set_bi(user: current_user, id: params[:id], value: params[:value])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Project.represent(result[:data])
        end

        # --- Logo do projeto (DB-089 / OPS-088) ------------------------------
        desc 'Envia o logo do projeto' do
          detail 'ActiveStorage no próprio model (DEC-91), 5 MB, com os derivados do legado. A ausência de ' \
                 'logo é EXPLÍCITA (`avatar_url: null`) — o legado tratava a string `"missing.jpg"` como ausência.'
        end
        params do
          requires :id, type: String
          requires :file, type: File
        end
        post ':id/logo' do
          authorize!(RESOURCE, :update)

          result = ProjectService.attach_avatar_file(user: current_user, id: params[:id], file: params[:file])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200

          # `POST` no Grape responde 201 por default. Aqui NÃO nasce recurso
          # novo: o registro é o mesmo, com um anexo a mais.
          status 200
          Api::Entities::Project.represent(result[:data])
        end

        desc 'Remove o logo do projeto'
        params { requires :id, type: String }
        delete ':id/logo' do
          authorize!(RESOURCE, :update)

          result = ProjectService.remove_avatar(user: current_user, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Project.represent(result[:data])
        end

        desc 'Limpa o projeto de treinamento' do
          summary 'Reset do projeto de treinamento'
          detail 'BE-092 — o projeto de treinamento NUNCA é removido, só limpo. O segmento aplicado depois da ' \
                 'limpeza é resolvido pela CHAVE de integração, nunca por id fixo: o legado tinha ' \
                 '`segment_id = 1` codificado (D-26).'
          failure [{ code: 422, message: 'Projeto que não é de treinamento' }]
        end
        params { requires :id, type: String }
        post ':id/reset' do
          authorize!(RESOURCE, :destroy)

          resultado = ProjectService.show(user: current_user, id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          reset = ProjectResetService.call(project: resultado[:data], actor: acting_user)
          error!(error_payload_for(reset), reset[:status]) if reset[:status] != 200

          # `POST` no Grape responde 201 por default, e aqui NÃO se cria
          # recurso: o projeto continua o mesmo, com os dados limpos.
          status 200
          reset[:data]
        end

        desc 'Remove um projeto' do
          detail 'Dependente vinculado responde **422 REAL** e o projeto PERMANECE (D-24). O projeto de ' \
                 'treinamento (`is_sandbox`) nunca é removido — a resposta diz para limpar.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)

          process_service_response(ProjectService.destroy(user: current_user, id: params[:id]))
        end
      end

      # BE-100 / DC-18 — a aba "Projetos" do detalhe de um usuário. É
      # **informativa** e mostra só o que o SOLICITANTE já poderia ver.
      namespace :users do
        before { authenticate_user! }

        desc 'Projetos de um usuário' do
          detail 'Interseção entre a participação do alvo e a visibilidade do solicitante.'
        end
        params { requires :id, type: String }
        get ':id/projects' do
          authorize!('users', :read)

          result = ProjectService.projects_of(actor: current_user, target_id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::ProjectOption.represent(result[:data])
        end
      end
    end
  end
end
