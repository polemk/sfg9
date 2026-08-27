# frozen_string_literal: true

module Api
  module Entities
    # S5 / BE-278 — tipo de limite de risco.
    #
    # `has_pre_faturamento` é exposta porque a tela precisa dela para decidir se
    # mostra os campos de "Saldo Inicial" no formulário de limite (FE-245) — e
    # porque, sendo **imutável depois do create**, a tela a apresenta como
    # somente leitura na edição.
    class RiskOperationType < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'CONGELADA na criação. Contrato: fomento, comissaria, intercompany, auto_liquidavel.' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :is_default,
             documentation: { type: 'Boolean', desc: 'Linha semeada pelo sistema — não pode ser removida.' }
      expose :allow_manual_operations,
             documentation: { type: 'Boolean', desc: 'Permite lançar operação de risco à mão (S7).' }
      expose :allow_receivable_entries,
             documentation: { type: 'Boolean', desc: 'Permite criar operação a partir do recebível (S6).' }
      expose :has_pre_faturamento,
             documentation: { type: 'Boolean', desc: 'Usa operações estáticas. IMUTÁVEL depois do create.' }
      expose :subtypes, using: Api::Entities::RiskOperationSubtype,
                        documentation: { type: 'Array', desc: '1 ou 2 subtipos, gerados pelo próprio tipo.' }
      expose :dependents_count,
             documentation: { type: 'Integer', desc: 'Limites e operações que usam este tipo — é o que bloqueia a exclusão.' } do |type, options|
        (options[:usage] || {})[type.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
