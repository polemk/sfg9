# frozen_string_literal: true

module Api
  module V1
    # S3 — a fiação comum dos **cinco catálogos globais**.
    #
    # Existe para que "listar um catálogo" signifique exatamente a mesma coisa
    # nos cinco endpoints: mesma paginação (Kaminari + envelope em cabeçalho,
    # DEC-62), mesma contagem de uso em UMA consulta, mesmo formato de erro.
    # O legado chegou a `prepare_ordering` copiado idêntico em **18 models**
    # porque não havia um lugar assim.
    #
    # **Nada aqui chama `current_project!`** — e isso é a decisão, não um
    # esquecimento. Catálogo global não recebe escopo de projeto (contrato C1,
    # regra 4 de `§0.6`): o menu esconde a tela de administração do catálogo,
    # não o dado do catálogo (DEC-18.4). A regra oposta,
    # `Model.for_project(current_project!)`, vale nas fatias S4 e S11.
    module CatalogHelpers
      include Api::V1::ControllerHelpers

      # Lista paginada + serialização com a contagem de uso da PÁGINA.
      #
      # `paginate` (do `ControllerHelpers`) é quem aplica `page`/`per_page` e
      # emite `X-Total-Count`/`X-Page`/`X-Per-Page`/`X-Total-Pages`. O total do
      # cabeçalho é o total **sem limite** — no legado `limit`/`offset` eram
      # lidos e descartados, e a UI de paginação era decorativa (D-20).
      def render_catalog_page(service, entity)
        result = service.index(params: params)
        registros = paginate(result[:data])
        lista = registros.to_a
        entity.represent(lista, usage: service.usage_counts(lista.map(&:id)))
      end

      # Um registro, ou 404. Serve `GET /:id` e o `#form` de edição — que no
      # legado respondia `MissingTemplate` → **500** em vez de 404 (BE-702).
      def render_catalog_record(service, entity, id)
        result = service.show(id: id)
        error!(error_payload_for(result), result[:status]) if result[:status] != 200
        entity.represent(result[:data], usage: service.usage_counts([result[:data].id]))
      end

      # Resposta de escrita: 201/200 com o registro, ou o erro do serviço já no
      # formato único `{error, message, code, details}`.
      def render_catalog_write(result, entity, expected:)
        error!(error_payload_for(result), result[:status]) if result[:status] != expected

        status expected
        entity.represent(result[:data])
      end
    end
  end
end
