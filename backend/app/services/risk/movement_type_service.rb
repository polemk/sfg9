# frozen_string_literal: true

module Risk
  # S5 / BE-279 — **tipos de movimentação de risco**. Catálogo GLOBAL.
  #
  # Duas coisas que o legado não tinha e entram aqui:
  #
  # 1. **Filtro por `is_active`.** A tela de tipos de movimento lista
  #    `RiskMovementType.all` — inclusive os desativados, sem nenhuma marca
  #    visual e sem filtro. A tela irmã (tipos de limite) lista só
  #    `RiskOperationType.active`. As duas telas do mesmo cadastro discordavam
  #    sobre o que é "a lista"; aqui o filtro é do cliente, e o padrão é listar
  #    tudo com o estado visível.
  # 2. **`destroy` que não mente.** No legado o `destroy` chama `destroy` **duas
  #    vezes** e o ramo de erro responde **`:ok`**
  #    (`risk_movement_types_controller.rb:98-112`): tentar remover um tipo
  #    padrão devolvia sucesso e a tela dizia "removido". Aqui é o `destroy` do
  #    `CatalogService`, que responde 422 real com a frase que nomeia o motivo
  #    (D-24).
  class MovementTypeService < CatalogService
    class << self
      def model = ::RiskMovementType
      def resource_label = 'Tipo de movimentação'

      def writable_attributes
        %i[title integration_key is_active credit_type is_system_exclusive is_transfer]
      end

      def filter(scope, params)
        scope = scope.where(credit_type: params[:credit_type]) if params[:credit_type].present?
        scope = scope.where(is_transfer: truthy?(params[:is_transfer])) unless params[:is_transfer].nil?
        scope
      end
    end
  end
end
