# frozen_string_literal: true

module Api
  module Entities
    # S5 / BE-279 — tipo de movimentação de risco.
    #
    # `credit_type_description` é **derivada** do `credit_type` (era coluna no
    # legado, gravada uma vez no create e nunca recalculada — trocar o tipo de
    # crédito na edição deixava a descrição errada para sempre).
    class RiskMovementType < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'CONGELADA. É por ela que os três tipos funcionais são resolvidos (B-09).' }
      # **O valor GRAVADO, não o rótulo do enum.** `tipo.credit_type` devolve
      # `'debit'`; o contrato com a tela, com o ETL e com o legado é `'D'`.
      expose :credit_type, documentation: { type: 'String', desc: "'C' = crédito (−1 no saldo) · 'D' = débito (+1)" } do |t|
        t.credit_type_code
      end
      expose :credit_type_description,
             documentation: { type: 'String', desc: 'Derivada do credit_type — não é coluna.' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :is_default, documentation: { type: 'Boolean', desc: 'Linha semeada — não pode ser removida.' }
      expose :is_system_exclusive,
             documentation: { type: 'Boolean', desc: 'Só o sistema lança. Não aparece no formulário manual.' }
      expose :is_transfer,
             documentation: { type: 'Boolean', desc: 'Transferência entre o par pré/antecipação. Dispara o espelho (S7).' }
      expose :dependents_count,
             documentation: { type: 'Integer', desc: 'Movimentos que usam este tipo — é o que bloqueia a exclusão.' } do |type, options|
        (options[:usage] || {})[type.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
