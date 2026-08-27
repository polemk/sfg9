# frozen_string_literal: true

module Api
  module Entities
    # S8 / **BE-296**…**BE-299** — tipo de operação estruturada.
    #
    # `is_default` é exposta porque é ela que decide se a tela mostra "Excluir"
    # — e como os **quatro** tipos semeados são `is_default`, na prática o botão
    # nunca aparece. A tela diz por quê em vez de o botão sumir sem explicação
    # (FE-300).
    class StructuredOperationType < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'IMUTÁVEL depois do create (BE-298)' }
      expose :integration_key,
             documentation: { type: 'String',
                              desc: 'CONGELADA na criação. Contrato: fomento, comissaria, intercompany, auto_liquidavel.' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :is_default,
             documentation: { type: 'Boolean', desc: 'Semeado pelo sistema — não removível. Os 4 tipos são todos `true`.' }
      expose :allow_manual_operations,
             documentation: { type: 'Boolean', desc: 'Sem consumidor no sistema (Q-R15) — coluna migrada, não regra.' }
      expose :allow_receivable_entries,
             documentation: { type: 'Boolean', desc: 'Sem consumidor no sistema (Q-R15).' }
      expose :has_pre_faturamento,
             documentation: { type: 'Boolean',
                              desc: 'Sem consumidor. Diferente do homônimo de `risk_operation_types`: aqui NÃO gera subtipo nem muda bucket.' }
      expose :dependents_count,
             documentation: { type: 'Integer', desc: 'Operações estruturadas que usam este tipo — é o que bloqueia a exclusão.' } do |type, options|
        (options[:usage] || {})[type.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
