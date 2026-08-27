# frozen_string_literal: true

# S6 / **BE-186**, **BE-446**, **BE-447**, **BE-448** — tipos de movimentação.
# Catálogo GLOBAL.
#
# Além do molde, este tem os **quatro classificadores** e o sentido contábil.
# A exclusividade (`BE-447`) é validada no model com mensagem pt-BR e fechada
# por `check_constraint` no banco.
class MovementKindService < CatalogService
  class << self
    def model = ::MovementKind
    def resource_label = 'Tipo de movimentação'

    def writable_attributes
      super + %i[kind is_operation is_title is_advalorem is_desagio is_iof is_liquidation]
    end

    # O filtro que a tela de borderô usa: só os tipos marcados como
    # `is_operation` entram na lista de tarifas. É o único dos flags de
    # exibição do legado que tem leitor.
    def filter(scope, params)
      return scope unless truthy?(params[:for_operation])

      scope.for_operation
    end
  end
end
