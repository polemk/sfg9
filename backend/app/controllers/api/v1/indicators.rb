# frozen_string_literal: true

module Api
  module V1
    # S10 / BE-311..BE-319, BE-717 — **o catálogo de indicadores**.
    #
    # **Catálogo GLOBAL: este endpoint não chama `current_project!` para listar
    # nem para ler** (contrato C1, regra 4). O Colaborador LÊ (DEC-18.4) — é o
    # que faz o dropdown dele subir populado —, e escreve quem a
    # `Authorization::Matrix` permitir (`indicators` → og/admin/gerente CRUD,
    # colaborador R).
    #
    # ## O gap de segurança que este arquivo fecha (BE-717)
    #
    # No legado **toda a autorização deste módulo é de view**: nenhum dos três
    # controllers (`indicators`, `indicator_entries`,
    # `project_indicator_connections`) tem um único `before_action` de permissão.
    # `user_is_readonly` apenas desabilita botões no HTML. Qualquer sessão
    # autenticada podia `POST /indicators` direto. Aqui cada verbo passa por
    # `authorize!`, e o `require_not_readonly!` global do `Api::V1::Base` cobre
    # o readonly.
    #
    # ## O projeto NUNCA vem do corpo
    #
    # Criar um indicador **específico** é `scope: 'project'`, e o projeto é o
    # `current_project!`. O `project_id` do formulário do legado
    # (`indicator_params`, `:143`) não existe aqui — era ele que permitia criar
    # indicador dentro de projeto alheio.
    class Indicators < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'indicators'

      namespace :indicators do
        before { authenticate_user! }

        desc 'Lista os indicadores GLOBAIS' do
          summary 'Catálogo de indicadores'
          detail 'Só `project_id IS NULL` — os específicos aparecem na tela de conexões do projeto. ' \
                 'Paginação REAL com X-Total-Count: o legado mandava `l=50, o=0` fixos e nunca ' \
                 'incrementava o offset, então a lista truncava em 50 sem aviso nenhum.'
          success [code: 200, model: Api::Entities::Indicator]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :active, type: Boolean, desc: 'Só os ativos'
          optional :ordering_keys, type: Array[String], desc: 'title | key | created_at'
          optional :ordering_style, type: Array[String], desc: 'up | down'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)

          escopo = ::Indicators::IndicatorService.index(params: params)[:data]
          lista = paginate(escopo).to_a
          ids = lista.map(&:id)
          Api::Entities::Indicator.represent(
            lista,
            entry_usage: ::Indicators::IndicatorService.entry_counts(ids),
            connection_usage: ::Indicators::IndicatorService.connection_counts(ids)
          )
        end

        desc 'Detalhe de um indicador' do
          detail 'BE-315 — 404 estruturado. No legado `GET /indicators/:id` renderizava um diretório ' \
                 'inexistente (`.../detail/body`) e o `#show` nem carregava `@indicator`: 500 sempre (BE-313).'
        end
        params { requires :id, type: String, desc: 'UUID do indicador' }
        get ':id' do
          authorize!(RESOURCE, :read)

          resultado = ::Indicators::IndicatorService.show(id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          Api::Entities::Indicator.represent(
            resultado[:data],
            entry_usage: ::Indicators::IndicatorService.entry_counts([resultado[:data].id]),
            connection_usage: ::Indicators::IndicatorService.connection_counts([resultado[:data].id])
          )
        end

        desc 'O que uma exclusão afeta — ANTES de qualquer escrita' do
          detail 'FE-315, o D-66 na copy. A confirmação do legado dizia apenas "A operação não pode ser ' \
                 'desfeita" e NÃO mencionava que todos os lançamentos históricos iriam junto ' \
                 '(`dependent: :delete_all`). Aqui a tela diz quantos lançamentos e quais projetos.'
        end
        params { requires :id, type: String, desc: 'UUID do indicador' }
        get ':id/deletion_impact' do
          authorize!(RESOURCE, :read)

          resultado = ::Indicators::IndicatorService.deletion_impact(id: params[:id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end

        desc 'Cria um indicador' do
          detail 'Transacional com a conexão de projeto: no legado, se o `Indicator.create` falhava, ' \
                 'ele ainda tentava `ProjectIndicatorConnection.create(indicator_id: nil, …)`, que falhava ' \
                 'em silêncio — e depois chamava `destroy` num objeto não persistido. ' \
                 '`scope: "project"` usa o PROJETO CORRENTE; o `project_id` do corpo não existe (C1).'
        end
        params do
          requires :title, type: String, desc: 'Vira CAIXA ALTA sem acento (DEC-89)'
          optional :key, type: String, desc: 'Chave de Integração. Em branco, é derivada do título'
          optional :is_active, type: Boolean, default: true
          optional :description, type: String, desc: 'Instrução em rich text (ActionText)'
          optional :scope, type: String, values: %w[global project], default: 'global',
                           desc: '`project` cria um indicador ESPECÍFICO do projeto corrente, com a conexão'
        end
        post '' do
          authorize!(RESOURCE, :create)

          projeto = params[:scope] == 'project' ? current_project! : nil
          attrs = declared(params, include_missing: false).symbolize_keys.except(:scope)
          resultado = ::Indicators::IndicatorService.create(attrs: attrs, project: projeto, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 201

          status 201
          Api::Entities::Indicator.represent(resultado[:data])
        end

        desc 'Atualiza um indicador' do
          detail 'UM save (o legado chamava `update` e `save`, e o `after_save` de propagação rodava DUAS ' \
                 'vezes). Mudar o alcance passa a SINCRONIZAR a conexão: no legado o indicador virava ' \
                 'específico sem conexão e SUMIA da tela do projeto.'
        end
        params do
          requires :id, type: String, desc: 'UUID do indicador'
          optional :title, type: String
          optional :is_active, type: Boolean
          optional :description, type: String
          optional :scope, type: String, values: %w[global project],
                           desc: 'Omitido = não mexe no alcance'
        end
        put ':id' do
          authorize!(RESOURCE, :update)

          mudanca = params[:scope].present? ? params[:scope].to_sym : nil
          projeto = mudanca == :project ? current_project! : nil
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id, :scope)

          resultado = ::Indicators::IndicatorService.update(id: params[:id], attrs: attrs, project: projeto,
                                                          scope_change: mudanca, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::Indicator.represent(resultado[:data])
        end

        desc 'Ativa ou desativa um indicador' do
          detail 'BE-319 — id inexistente deixa de ser `nil.is_active=` → 500. E `is_active` é BOOLEAN: ' \
                 'no legado era integer livre e `is_active?` só considerava `== 1`, então 2 ou −1 contavam ' \
                 'como inativo em silêncio.'
        end
        params do
          requires :id, type: String, desc: 'UUID do indicador'
          requires :is_active, type: Boolean
        end
        put ':id/activation' do
          authorize!(RESOURCE, :update)

          resultado = ::Indicators::IndicatorService.activate(id: params[:id], is_active: params[:is_active],
                                                            actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::Indicator.represent(resultado[:data])
        end

        desc 'Exclui um indicador — exclusão LÓGICA (D-66)' do
          detail 'O legado apagava o indicador E TODA A SÉRIE HISTÓRICA (`dependent: :delete_all`, sem ' \
                 'callbacks e sem backup), e respondia `:ok` nos dois ramos. Aqui o registro é marcado ' \
                 'como descartado, os lançamentos FICAM, e o erro é 422 de verdade.'
        end
        params { requires :id, type: String, desc: 'UUID do indicador' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)

          resultado = ::Indicators::IndicatorService.destroy(id: params[:id], actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end
      end
    end
  end
end
