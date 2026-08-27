# frozen_string_literal: true

module Api
  module V1
    # S11 / BE-110..116, BE-140..148 — **os padrões de disponibilidade do
    # projeto** ("Disponibilidades" e "Disponibilidades do Projeto").
    #
    # **Toda ação declara `project = current_project!` numa linha visível**, e o
    # `project_id` que vier no corpo nem é declarado nos `params do` (contrato
    # C1). É a regra **oposta** à de `Api::V1::AvailabilityTemplates`, e as duas
    # estão certas.
    #
    # ## O que muda em relação ao legado
    #
    # | Defeito | No legado |
    # | ------- | --------- |
    # | **BE-110** | `Project.find(current_user.default_project.id)` — sem projeto corrente, `NoMethodError` → 500. E a ordem vinha de `all_ids_by_position`, que faz uma consulta por nó e monta `join (VALUES …)` por interpolação; com projeto zerado o `VALUES ()` vira **SQL inválido** |
    # | **BE-142 / D-23 / D-29** | `:id` **dentro** do `permit` (mass assignment de chave primária) e `:project_id` também: criar padrão em projeto alheio era um campo escondido de formulário |
    # | **BE-144** | `Delayed::Job.enqueue` era chamado sempre, e o `unless job.nil?` tratava falha de enfileiramento como **sucesso** — a tela dizia "ativado" e nada acontecia |
    # | **D-04 / D-33** | a guarda de obrigatoriedade existia num método que nenhum caminho real chamava. Aqui ela roda **no serviço, antes de enfileirar** |
    class ProjectAvailabilities < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'project_availabilities'

      namespace :project_availabilities do
        before { authenticate_user! }

        desc 'Árvore de padrões de disponibilidade do projeto corrente' do
          summary 'Disponibilidades do projeto'
          detail 'BE-110 / BE-140 — árvore ordenada por `sort_key`, numa consulta. Projeto zerado ' \
                 'devolve lista vazia, nunca SQL inválido.'
          success [code: 200, model: Api::Entities::AvailabilityTemplate]
          is_array true
        end
        params do
          optional :q, type: String
          optional :is_active, type: Boolean
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 100
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          escopo = ::Availability::ProjectTemplateService.tree(project: project, params: params)[:data]
          Api::Entities::AvailabilityTemplate.represent(paginate(escopo).to_a)
        end

        desc 'Pais válidos para um nível, NESTE projeto' do
          detail 'BE-111 / FE-110 / FE-148 — **nenhum padrão de outro projeto no payload**. O legado ' \
                 'embutia `AvailabilityTemplate.all` num atributo `data-templates` do HTML e o ' \
                 'filtro de níveis rodava sobre esse JSON global.'
        end
        params { optional :level, type: Integer, values: 1..3 }
        get 'available_parents' do
          authorize!(RESOURCE, :read)
          project = current_project!

          Api::Entities::AvailabilityTemplate.represent(
            ::Availability::ProjectTemplateService.available_parents(project: project,
                                                                   level: params[:level]).to_a
          )
        end

        desc 'Detalhe de um padrão do projeto'
        params { requires :id, type: String }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          resultado = ::Availability::ProjectTemplateService.show(project: project, id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Cria um padrão de disponibilidade no projeto corrente' do
          detail 'BE-112 / BE-142 — projeto **do servidor**; `:id` e `project_id` não são declarados. ' \
                 'Pai de outro projeto é RECUSADO (FE-148 pelo lado do servidor).'
        end
        params do
          requires :title, type: String
          requires :operation_type, type: String, values: %w[C D S M]
          requires :deadline_type, type: String, values: %w[CP LP]
          optional :parent_template_id, type: String
          # **`is_mandatory` NÃO é declarado — BE-112/BE-142, DEC-30.**
          #
          # O `permit` do legado para o padrão de PROJETO
          # (`project_availabilities_controller.rb:143-155`) não tem o campo; só
          # o do catálogo GLOBAL tem. A obrigatoriedade é atributo da origem: um
          # padrão de projeto é obrigatório porque veio de um global obrigatório,
          # não porque alguém marcou uma caixa no formulário do projeto.
          #
          # Aqui ele estava declarado no `create` **e não no `update`** — a
          # assimetria é o que denuncia o descuido, não uma decisão. A tela
          # nunca ofereceu o controle: `ProjectAvailabilitiesPage` só LÊ o campo
          # (o selo "Obrigatório" e a trava de desativação) e manda `false` fixo.
          # Era superfície de escrita que o legado não tinha e que ninguém usava.
          #
          # A coluna é `null: false, default: false` no banco, então o registro
          # nasce não obrigatório sem precisar de parâmetro.
          optional :is_cumulative, type: Boolean, default: true
          optional :is_adjusted, type: Boolean, default: false
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          resultado = ::Availability::ProjectTemplateService.create(project: project, attrs: attrs,
                                                                  actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 201

          status 201
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Renomeia um padrão do projeto' do
          detail 'BE-143 / DC-24 / DC-32 — **só o título muda**, e renomear NÃO renumera. Padrão ' \
                 'bloqueado por job responde **409**.'
        end
        params do
          requires :id, type: String
          requires :title, type: String
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          resultado = ::Availability::ProjectTemplateService.update(project: project, id: params[:id],
                                                                   attrs: attrs, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Reordena um padrão dentro do grupo de irmãos' do
          detail 'BE-116 / BE-138 — recusado no servidor quando inválido.'
        end
        params do
          requires :id, type: String
          requires :position, type: Integer
        end
        put ':id/position' do
          authorize!(RESOURCE, :update)
          project = current_project!

          resultado = ::Availability::ProjectTemplateService.move(project: project, id: params[:id],
                                                                 position: params[:position])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Ativa um padrão do projeto' do
          detail 'BE-144 / DC-33 — **idempotente**: a segunda ativação responde 409, não um segundo ' \
                 'job. Pai inativo → 422 com orientação. O progresso chega por Action Cable ' \
                 '(`ProjectProgressChannel`), nunca por polling.'
        end
        params { requires :id, type: String }
        post ':id/activate' do
          authorize!(RESOURCE, :update)
          project = current_project!

          resultado = ::Availability::ProjectTemplateService.activate(project: project, id: params[:id],
                                                                     actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 202

          status 202
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Desativa um padrão do projeto' do
          detail 'BE-145 / D-04 / D-33 — obrigatório e com dependente obrigatório são recusados **no ' \
                 'serviço**, antes de enfileirar: nenhum job entra na fila.'
        end
        params { requires :id, type: String }
        post ':id/deactivate' do
          authorize!(RESOURCE, :update)
          project = current_project!

          resultado = ::Availability::ProjectTemplateService.deactivate(project: project, id: params[:id],
                                                                       actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 202

          status 202
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Remove um padrão do projeto' do
          detail 'BE-146 / DC-20 — padrão **com lançamentos** responde 422 e os lançamentos ' \
                 'PERMANECEM. O legado apagava `entries.destroy_all` contornando o próprio ' \
                 '`restrict_with_error`. Padrão de origem global não é removível por aqui.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          resultado = ::Availability::ProjectTemplateService.destroy(project: project, id: params[:id],
                                                                    actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 202

          status 202
          resultado[:data]
        end
      end
    end
  end
end
