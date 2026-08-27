# frozen_string_literal: true

module Api
  module Entities
    # S5 / BE-278 — subtipo de limite.
    #
    # O subtipo não é cadastrado à mão: nasce do `after_create` do tipo pai. Ele
    # é exposto porque é o que decide o **bucket** da operação no painel
    # (liquidável × pré-faturamento) e a S7 precisa dele no formulário.
    class RiskOperationSubtype < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String' }
      expose :integration_key, documentation: { type: 'String' }
      expose :is_pre,
             documentation: { type: 'Boolean', desc: 'true = pré-faturamento; false = antecipação/liquidável' }
      expose :is_default_for_type,
             documentation: { type: 'Boolean', desc: 'DEC-67 — o subtipo assumido quando o formulário não pergunta' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :allow_manual_operations, documentation: { type: 'Boolean' }
      expose :allow_receivable_entries, documentation: { type: 'Boolean' }
      expose :pair_id, documentation: { type: 'String', desc: 'O outro subtipo do par. Nulo em tipo sem pré-faturamento.' }
      expose :risk_operation_type_id, documentation: { type: 'String' }
    end
  end
end
