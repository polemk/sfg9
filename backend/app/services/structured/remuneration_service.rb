# frozen_string_literal: true

module Structured
  # S8 / **BE-300**…**BE-304** — as **remunerações** de um projeto.
  #
  # Escopado por projeto (contrato **C1**), por isso herda de
  # `ProjectScopedService` e **não** de `CatalogService`: uma taxa vale para um
  # projeto, e vazá-la entre projetos é vazar preço de cliente.
  #
  # ## O que muda em relação ao legado, e por quê
  #
  # | Legado (`pub/remunerations_controller.rb`) | ai9 |
  # | --- | --- |
  # | `project_id` vem de **campo hidden** e não é conferido (BE-301) | forçado ao projeto corrente pelo `ProjectScopedService` |
  # | `update` busca **sem** escopo (BE-302) | busca dentro do escopo; id alheio é 404, igual a inexistente |
  # | `operation_type_type` aceita string arbitrária | `inclusion` no model + `check_constraint` no banco → **422** |
  # | `index` sem paginação, sem `ORDER BY`, sem total (BE-300) | os três, mais filtro por classe e busca textual |
  # | `has_many :receipts` **sem** `dependent:` (BE-303) | `restrict_with_error` → **422 nomeando o vínculo** |
  #
  # ## A imutabilidade que o formulário promete passa a valer no servidor
  #
  # `#update` aceita **trocar o tipo**, como o legado — e isso **não** recalcula
  # recibo já emitido. É replicado de propósito: o recibo **congela** `fee`,
  # `title` e `kind` na emissão (`receipt.rb:57-62`), então o histórico
  # continua correto sozinho. Recalcular seria reescrever o que já foi cobrado.
  class RemunerationService < ProjectScopedService
    class << self
      def model = ::Remuneration
      def resource_label = 'Remuneração'
      def resource_genero = :feminino

      # `title` **não** entra: é derivado do tipo em todo save (DB-285/B-06).
      # `project_id`, `user_id` e `id` também não — os três vêm do servidor.
      def writable_attributes
        %i[operation_type_type operation_type_id value]
      end

      # BE-300 — o filtro por classe, que o legado não tinha: LIQ e EST vinham
      # juntas na mesma lista, sem como separar.
      def filter(scope, params)
        scope = scope.of_kind(params[:operation_type_type]) if params[:operation_type_type].present?
        scope
      end

      # A listagem carrega o tipo junto. Sem isto, `beauty_type` e o título do
      # tipo na tela seriam uma consulta por linha — e o polimorfismo faz o
      # `includes` do ActiveRecord virar duas consultas (uma por classe de
      # tipo), que é o certo aqui.
      def base_scope(project)
        model.for_project(project).includes(:operation_type)
      end
    end
  end
end
