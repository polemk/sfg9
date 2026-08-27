# frozen_string_literal: true

module Api
  module Entities
    # S7 / **FE-274** — **prorrogação** de vencimento.
    #
    # A lista da aba PRORROGAÇÕES: "Prorrogado Em", "Data Original", "Nova Data",
    # "Observação". O registro é **imutável** — não há endpoint de edição nem de
    # exclusão, como no legado. Corrigir uma prorrogação é lançar outra, e é isso
    # que preserva a contagem que a coluna "Prorrogações" da lista mostra.
    class RiskOperationExtension < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :risk_operation_id, documentation: { type: 'String' }
      expose :original_due_date,
             documentation: { type: 'Date', desc: 'Carimbado DA OPERAÇÃO; o valor do formulário é ignorado.' }
      expose :new_due_date, documentation: { type: 'Date' }
      expose :observation, documentation: { type: 'String' } do |e|
        e.observation.to_s
      end

      expose :user_id, documentation: { type: 'String' }
      expose :user_name, documentation: { type: 'String' } do |e|
        e.author&.name
      end

      expose :created_at, documentation: { type: 'DateTime', desc: '"Prorrogado Em" na tela.' }
    end
  end
end
