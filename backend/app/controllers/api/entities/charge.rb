# frozen_string_literal: true

module Api
  module Entities
    # S6 / BE-187 — pacote de cobrança.
    #
    # ⚠ NUNCA EXECUTADO EM PRODUÇÃO (DEC-103b): a tabela `charges` não existe
    # no banco de produção.
    class Charge < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :date, documentation: { type: 'Date', desc: 'Data da cobrança' }
      expose :state, documentation: { type: 'String', desc: 'editing | available | done' }
      expose :state_label, documentation: { type: 'String', desc: 'Rótulo pt-BR: Edição | Disponível | Faturado' }
      expose :done, documentation: { type: 'Boolean', desc: 'Faturada. Bloqueia alteração NO SERVIDOR (D-18)' } do |c|
        c.done?
      end

      expose :value, documentation: { type: 'BigDecimal', desc: 'Total cobrado — soma do valor dos recibos' }
      expose :risk_operations_value, documentation: { type: 'BigDecimal', desc: 'Valor das operações de risco (LIQ)' }
      expose :structured_operations_value, documentation: { type: 'BigDecimal', desc: 'Valor das estruturadas (EST)' }
      expose :total_operations_value, documentation: { type: 'BigDecimal', desc: 'Risco + estruturadas' }
      expose :receipts_count, documentation: { type: 'Integer' }
      expose :risk_operations_count, documentation: { type: 'Integer' }
      expose :structured_operations_count, documentation: { type: 'Integer' }

      expose :user_id, documentation: { type: 'String', desc: 'Autor. Vem da sessão' }
      expose :created_at
      expose :updated_at
    end
  end
end
