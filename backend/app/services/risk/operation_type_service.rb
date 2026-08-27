# frozen_string_literal: true

module Risk
  # S5 / BE-278 — **tipos de limite**. Catálogo GLOBAL (molde `CatalogService`).
  #
  # A única regra própria: **`has_pre_faturamento` não entra no update**.
  #
  # No legado ela está no `permit` (`risk_operation_types_controller.rb:135`) e o
  # formulário de edição a oferece. Mudá-la em um tipo que já tem operações
  # gravadas:
  #
  # - não cria nem remove subtipo (o `after_create` só roda na criação), então o
  #   tipo fica com o número errado deles;
  # - troca, **em silêncio**, o bucket em que toda operação daquele tipo passa a
  #   somar no painel de exposição — ligar o pré-faturamento faz
  #   `limite_liquidavel_on` deixar de somar as operações cujo subtipo não está
  #   na lista `is_pre = 0`, e o número da tela muda sem nenhum lançamento novo.
  #
  # É correção de **integridade de dado**, não de cálculo: nada muda para quem
  # não tentar editar a flag. Quem precisa de outro comportamento cria outro
  # tipo — que é barato, porque o cadastro é aberto desde 2022.
  class OperationTypeService < CatalogService
    class << self
      def model = ::RiskOperationType
      def resource_label = 'Tipo de limite'

      def writable_attributes
        %i[title integration_key is_active allow_manual_operations allow_receivable_entries]
      end

      # Só na criação. Ver o cabeçalho.
      def creatable_attributes
        writable_attributes + %i[has_pre_faturamento]
      end

      def create(attrs:, actor: nil)
        record = model.new
        creatable_attributes.each do |atributo|
          record.public_send(:"#{atributo}=", attrs[atributo]) if attrs.key?(atributo)
        end
        record.user_id = actor&.id

        return unprocessable(record) unless save_safely(record)

        { status: 201, data: record.reload }
      end

      def filter(scope, params)
        scope = scope.where(has_pre_faturamento: truthy?(params[:has_pre])) if params.key?(:has_pre) && !params[:has_pre].nil?
        scope
      end
    end
  end
end
