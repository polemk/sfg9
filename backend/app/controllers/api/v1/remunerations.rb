# frozen_string_literal: true

module Api
  module V1
    # S8 / **BE-300**…**BE-304**, **FE-309** — as **remunerações** do projeto.
    #
    # Escopada por projeto (**C1**): `project = current_project!` em toda ação, e
    # o `project_id` do corpo **nem é declarado**. No legado ele vinha de um
    # `hidden_field` e não era conferido — dava para criar remuneração em outro
    # projeto trocando o valor do campo (BE-301). É preço de cliente.
    class Remunerations < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'remunerations'

      namespace :remunerations do
        before { authenticate_user! }

        desc 'Lista as remunerações do projeto corrente' do
          summary 'Remunerações'
          detail 'BE-300 — o legado **não tinha nenhum dos três**: paginação, `ORDER BY` e total. Ganha também ' \
                 'o filtro por classe (LIQ/EST), que não existia: as duas vinham juntas na mesma lista.'
          success [code: 200, model: Api::Entities::Remuneration]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca no título (a coluna desnormalizada — B-06)'
          optional :operation_type_type, type: String, values: ::Remuneration::OPERATION_TYPE_TYPES,
                                         desc: 'RiskOperationType (LIQ) | StructuredOperationType (EST)'
          optional :ordering_keys, type: Array[String], values: ::Remuneration::ORDERING.allowed.keys,
                                   desc: 'title | kind | value | created_at — chave fora da lista responde 400'
          optional :ordering_style, type: Array[String], values: %w[up down asc desc ascending descending]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = Structured::RemunerationService.index(project: project, params: params)[:data]
          Api::Entities::Remuneration.represent(paginate(scope).to_a)
        end

        desc 'Tipos disponíveis para receber remuneração' do
          detail 'Alimenta o select do painel lateral. **Q-R21** — na edição o tipo já escolhido aparece mesmo ' \
                 'desativado (senão o select da edição fica vazio e o campo some do submit), mas tipo ' \
                 'desativado não é oferecido para uma remuneração nova.'
        end
        params do
          requires :operation_type_type, type: String, values: ::Remuneration::OPERATION_TYPE_TYPES
          optional :include_id, type: String, desc: 'UUID do tipo já selecionado — entra mesmo se inativo'
        end
        get 'operation_types' do
          authorize!(RESOURCE, :read)
          current_project!

          # De-para explícito, **não `constantize`**: mesmo com o `values:` do
          # Grape barrando a entrada, constantizar string de requisição é o
          # padrão que vira RCE no dia em que alguém afrouxar a validação.
          klass = { ::Remuneration::RISK_TYPE => ::RiskOperationType,
                    ::Remuneration::STRUCTURED_TYPE => ::StructuredOperationType }
                  .fetch(params[:operation_type_type])
          escopo = klass.where(is_active: true)
          escopo = klass.where(id: [*escopo.ids, params[:include_id]]) if params[:include_id].present?

          escopo.order(:title).map { |t| { id: t.id, title: t.title, is_active: t.is_active } }
        end

        desc 'Detalhe de uma remuneração'
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Structured::RemunerationService.show(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Remuneration.represent(result[:data])
        end

        desc 'Cria uma remuneração' do
          detail 'BE-301 — `project_id` **forçado** ao projeto corrente (no legado vinha de campo hidden). ' \
                 '`operation_type_type` validado por **inclusão** (o legado aceitava valor arbitrário e depois ' \
                 'quebrava em `operation_class` nil e `beauty_type` "???"). ' \
                 'Unicidade (projeto, classe, tipo) no banco: é o que garante que `Receipt#fetch` ache UMA taxa. ' \
                 '**A faixa de `value` NÃO é validada** (T-D9): 250% passa hoje e continua passando — validar ' \
                 'recusaria registro que o sistema aceita.'
        end
        params do
          requires :operation_type_type, type: String, values: ::Remuneration::OPERATION_TYPE_TYPES
          requires :operation_type_id, type: String
          requires :value, type: BigDecimal, desc: 'Taxa em %. Sem limite superior nem inferior (T-D9).'
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          result = Structured::RemunerationService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::Remuneration.represent(result[:data])
        end

        desc 'Atualiza uma remuneração' do
          detail 'BE-302 — busca **com** escopo de projeto (o legado buscava sem, e dava para editar a taxa de ' \
                 'outro projeto sabendo o id). `title` é recalculado do tipo em todo save. **Trocar o tipo NÃO ' \
                 'recalcula recibo já emitido**: o recibo congela `fee`/`title`/`kind` na emissão, então o ' \
                 'histórico fica correto sozinho — replicado de propósito.'
        end
        params do
          requires :id, type: String
          optional :operation_type_type, type: String, values: ::Remuneration::OPERATION_TYPE_TYPES
          optional :operation_type_id, type: String
          optional :value, type: BigDecimal
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = Structured::RemunerationService.update(project: project, id: params[:id],
                                                          attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::Remuneration.represent(result[:data])
        end

        desc 'Remove uma remuneração' do
          detail 'BE-303 — com recibos emitidos, **422**. No legado `has_many :receipts` estava **sem ' \
                 '`dependent:`**: apagar a remuneração deixava recibo órfão, e como `Receipt belongs_to ' \
                 ':remuneration` é obrigatório, qualquer save posterior daquele recibo falhava.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          result = Structured::RemunerationService.destroy(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
