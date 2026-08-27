# frozen_string_literal: true

module Api
  module V1
    # S8 / **BE-308**, **BE-725**…**BE-729** — as **fontes de recurso**.
    #
    # A S6 montou só a leitura, por dependência dura:
    # `receivable_entries.resource_source_id` é obrigatório (28.131 de 28.131
    # linhas de produção têm valor) e sem um `GET` que popule o select o
    # formulário de borderô responde 422 no Salvar. **A S8 fecha o resto**:
    # `show` com 404 estruturado, painel lateral e as três escritas.
    #
    # **Catálogo GLOBAL**: não chama `current_project!` (C1, regra 4).
    #
    # ## Q-R19 — `is_active` continua não filtrando o select do borderô
    #
    # A fonte é **apenas classificatória**: não entra em nenhuma fórmula de
    # tarifa, IOF, custo efetivo ou remuneração. Se o select do borderô
    # passasse a filtrar por ativa, desativar uma fonte tornaria irreeditável
    # todo borderô histórico que a usa — o valor gravado sumiria das opções. O
    # `?active=true` existe para a tela de **administração**, que é outra coisa.
    class ResourceSources < Grape::API
      helpers Api::V1::CatalogHelpers

      RESOURCE = 'resource_sources'

      namespace :resource_sources do
        before { authenticate_user! }

        desc 'Lista fontes de recurso' do
          summary 'Fontes de recurso'
          detail 'Catálogo GLOBAL. Popula o select obrigatório do formulário de borderô — por isso a leitura ' \
                 'segue o gate de `receivables`, que é quem a consome.'
          success [code: 200, model: Api::Entities::ResourceSource]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca por título ou chave (ILIKE com bind)'
          optional :active, type: Boolean, desc: 'Só as ativas. Ausente = todas — é o que o borderô usa (Q-R19).'
          optional :ordering_keys, type: Array[String], values: ::ResourceSource::ORDERING.allowed.keys,
                                   desc: 'title | key | created_at — chave fora da lista responde 400'
          optional :ordering_style, type: Array[String], values: %w[up down asc desc ascending descending]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 50
        end
        get '' do
          # A leitura segue o gate de `receivables` porque é o borderô que a
          # consome; a ESCRITA usa a linha própria de `resource_sources` na
          # matriz (DEC-18), que é og/admin/gerente.
          authorize!('receivables', :read)
          render_catalog_page(ResourceSourceService, Api::Entities::ResourceSource)
        end

        desc 'Detalhe de uma fonte' do
          detail 'BE-726 — inexistente ou id malformado → **404 estruturado**. No legado o `show` renderizava ' \
                 'template inexistente e devolvia 500.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!('receivables', :read)
          render_catalog_record(ResourceSourceService, Api::Entities::ResourceSource, params[:id])
        end

        desc 'Cria uma fonte de recurso' do
          detail 'BE-727 — `title` obrigatório e único; `integration_key` derivada do título **no create** e ' \
                 'única. Sai o `destroy` em objeto não persistido que o controller legado chamava quando o ' \
                 'create falhava. `user_id` vem da SESSÃO.'
        end
        params do
          requires :title, type: String
          optional :integration_key, type: String, desc: 'Derivada do título quando ausente. IMUTÁVEL depois.'
          optional :is_active, type: Boolean, default: true
        end
        post '' do
          authorize!(RESOURCE, :create)
          attrs = declared(params, include_missing: false).symbolize_keys
          render_catalog_write(ResourceSourceService.create(attrs: attrs, actor: acting_user),
                               Api::Entities::ResourceSource, expected: 201)
        end

        desc 'Atualiza uma fonte de recurso' do
          detail 'BE-728 — **`integration_key` é recusada aqui, explicitamente.** Renomear o título NÃO mexe na ' \
                 'chave, porque é ela que os relatórios usam para casar a fonte com a origem. No legado isso ' \
                 'era acidental (o formulário simplesmente não mandava o campo); aqui é regra escrita. ' \
                 'Um save, não os três do legado.'
        end
        params do
          requires :id, type: String, desc: 'UUID do registro'
          optional :title, type: String
          # DECLARADA para ser **recusada com mensagem**. Fora do `params`, o
          # Grape a descartaria em silêncio e o cliente veria 200 sem que nada
          # tivesse mudado.
          optional :integration_key, type: String, desc: 'IMUTÁVEL — enviar responde 422 com o motivo'
          optional :is_active, type: Boolean
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          render_catalog_write(ResourceSourceService.update(id: params[:id], attrs: attrs, actor: acting_user),
                               Api::Entities::ResourceSource, expected: 200)
        end

        desc 'Remove uma fonte de recurso' do
          detail 'BE-729 — **aqui a guarda realmente dispara**, porque a coluna é preenchida em 28.131 de ' \
                 '28.131 borderôs: fonte em uso responde **422 com a dependência nomeada**. No legado os dois ' \
                 'ramos devolviam `:ok` e o usuário via a lista recarregar como se tivesse excluído.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          result = ResourceSourceService.destroy(id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
