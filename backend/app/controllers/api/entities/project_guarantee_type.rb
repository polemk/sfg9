# frozen_string_literal: true

module Api
  module Entities
    # S3 / BE-700 — tipo de garantia.
    #
    # `is_provisional` existe por causa do **DEC-86**: o conteúdo deste catálogo
    # é novo (no legado nenhum seed o popula e o select sobe vazio), e o que foi
    # semeado é suposição. A tela **mostra** isso ao usuário em vez de deixá-lo
    # descobrir depois que a lista não era a dele.
    class ProjectGuaranteeType < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'CONGELADA na criação (DC-22). Renomear o título não a recalcula.' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :is_provisional,
             documentation: { type: 'Boolean', desc: 'DEC-86 — semeado como suposição; a lista definitiva é do cliente.' }
      expose :sort_order, documentation: { type: 'Integer' }
      expose :description, documentation: { type: 'String' }
      expose :observation, documentation: { type: 'String' }
      expose :guarantees_count,
             documentation: { type: 'Integer', desc: 'Garantias de projeto que usam este tipo — é o que bloqueia a exclusão' } do |t, options|
        (options[:usage] || {})[t.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
