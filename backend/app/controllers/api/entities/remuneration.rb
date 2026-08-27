# frozen_string_literal: true

module Api
  module Entities
    # S8 / **BE-300**…**BE-304** — a remuneração.
    #
    # `beauty_type` (`LIQ`/`EST`) é exposta porque é a **coluna "Classe"** da
    # tela e porque é a sigla que o recibo persiste e que `Charge#calc!` usa
    # para separar os totais. No legado ela podia valer `"???"`; aqui o domínio
    # é fechado no banco e a sigla nunca é inventada.
    class Remuneration < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :project_id, documentation: { type: 'String', desc: 'Forçado ao projeto corrente (BE-301)' }
      expose :operation_type_type,
             documentation: { type: 'String', desc: 'RiskOperationType (LIQ) ou StructuredOperationType (EST)' }
      expose :operation_type_id, documentation: { type: 'String', desc: 'UUID do tipo' }
      expose :beauty_type, documentation: { type: 'String', desc: 'LIQ | EST — a sigla que o recibo congela' }
      expose :title,
             documentation: { type: 'String',
                              desc: 'DESNORMALIZADO do tipo, reescrito em todo save (B-06). É a coluna que a busca usa.' }
      expose :value,
             documentation: { type: 'BigDecimal',
                              desc: 'A taxa em %. SEM validação de faixa (T-D9): é a decisão do negócio, não da migração.' }
      expose :receipts_count,
             documentation: { type: 'Integer', desc: 'Recibos emitidos com esta taxa — é o que bloqueia a exclusão.' } do |r|
        r.receipts.size
      end
      expose :created_at
      expose :updated_at
    end
  end
end
