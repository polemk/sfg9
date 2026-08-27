# frozen_string_literal: true

module Api
  module V1
    # S11 / BE-132..139 — **o catálogo global de padrões de disponibilidade**
    # ("Tipos de disponibilidade").
    #
    # **Nenhuma ação aqui chama `current_project!`, e isso é a regra** (contrato
    # C1, regra 4 de `§0.6`): catálogo global não recebe escopo de projeto. É a
    # regra **oposta** à de `Api::V1::ProjectAvailabilities`, e as duas estão
    # certas — ver `app/models/global_availability_template.rb`.
    #
    # O que ele fecha: **D-06** (a busca com texto derrubava a requisição, porque
    # `where!("title #{Dev.ilike} ", "#{@query}%")` monta fragmento sem
    # placeholder), **D-07/D-20** (`l`/`o` lidos e nunca aplicados) e o
    # **BE-134** (`is_mandatory |= 1` — todo global nascia obrigatório —, mais o
    # `should_insert_on_existing_projects` com default 1 e nunca exposto, que
    # fazia **toda** criação enfileirar job em **todos** os projetos).
    class AvailabilityTemplates < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'availability_templates'

      namespace :availability_templates do
        before { authenticate_user! }

        desc 'Lista o catálogo global de padrões de disponibilidade' do
          summary 'Tipos de disponibilidade'
          detail 'BE-132 — busca por SUBSTRING, paginação e ordenação reais. A ordem padrão é ' \
                 '`default_position` (DEC-79) com a hierarquia como desempate.'
          success [code: 200, model: Api::Entities::AvailabilityTemplate]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por substring no título'
          optional :parent_id, type: String, desc: 'Filtra pelos filhos de um padrão'
          optional :is_active, type: Boolean
          optional :ordering_keys, type: Array[String]
          optional :ordering_style, type: Array[String]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)

          escopo = ::Availability::GlobalTemplateService.index(params: params)[:data]
          Api::Entities::AvailabilityTemplate.represent(paginate(escopo).to_a)
        end

        desc 'Pais válidos para um nível' do
          detail 'BE-111 — "Faz parte de" só oferece pai que pode ter filho. Um padrão de 3º nível ' \
                 'não aparece nunca.'
        end
        params { optional :level, type: Integer, values: 1..3 }
        get 'available_parents' do
          authorize!(RESOURCE, :read)

          Api::Entities::AvailabilityTemplate.represent(
            ::Availability::GlobalTemplateService.available_parents(level: params[:level]).to_a
          )
        end

        desc 'Detalhe de um padrão' do
          detail 'BE-133 — funciona **também** para padrão de projeto. No legado a view chamava ' \
                 '`.projects`, associação inexistente: `NoMethodError` ao abrir o detalhe.'
        end
        params { requires :id, type: String }
        get ':id' do
          authorize!(RESOURCE, :read)

          resultado = ::Availability::GlobalTemplateService.show(id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Cria um padrão global' do
          detail 'BE-134 — a obrigatoriedade escolhida É gravada, e a propagação para projetos ' \
                 'existentes é OPÇÃO do usuário (`should_insert_on_existing_projects`).'
        end
        params do
          requires :title, type: String
          requires :operation_type, type: String, values: %w[C D S M]
          requires :deadline_type, type: String, values: %w[CP LP]
          optional :parent_template_id, type: String
          optional :is_mandatory, type: Boolean, default: false
          optional :is_cumulative, type: Boolean, default: true
          optional :is_adjusted, type: Boolean, default: false
          optional :should_insert_on_existing_projects, type: Boolean, default: false
          optional :default_position, type: Integer
        end
        post '' do
          authorize!(RESOURCE, :create)

          attrs = declared(params, include_missing: false).symbolize_keys
          resultado = ::Availability::GlobalTemplateService.create(attrs: attrs, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 201

          status 201
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Atualiza um padrão global' do
          detail 'BE-135 / DC-31 — alterar `is_adjusted`/`is_cumulative` PROPAGA aos derivados, em ' \
                 'segundo plano. Hoje não propaga, e o catálogo mente sobre os padrões que gerou.'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :operation_type, type: String, values: %w[C D S M]
          optional :deadline_type, type: String, values: %w[CP LP]
          optional :parent_template_id, type: String
          optional :is_mandatory, type: Boolean
          optional :is_cumulative, type: Boolean
          optional :is_adjusted, type: Boolean
          optional :default_position, type: Integer
        end
        put ':id' do
          authorize!(RESOURCE, :update)

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          resultado = ::Availability::GlobalTemplateService.update(id: params[:id], attrs: attrs,
                                                                 actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Reordena um padrão global dentro do grupo de irmãos' do
          detail 'BE-138 — movimento inválido é RECUSADO no servidor. Sem tela nova (DC-21).'
        end
        params do
          requires :id, type: String
          requires :position, type: Integer
        end
        put ':id/position' do
          authorize!(RESOURCE, :update)

          resultado = ::Availability::GlobalTemplateService.move(id: params[:id], position: params[:position])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::AvailabilityTemplate.represent(resultado[:data])
        end

        desc 'Remove um padrão global' do
          detail 'BE-136 / D-24 — desvínculo em cascata TRANSACIONAL. Elimina a rotina manual ' \
                 '`fix_after_global_remove`, que existia porque o `update_all` do legado rodava ' \
                 'fora de qualquer transação.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)

          resultado = ::Availability::GlobalTemplateService.destroy(id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end
    end
  end
end
