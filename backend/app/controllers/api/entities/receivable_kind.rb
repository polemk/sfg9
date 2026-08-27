# frozen_string_literal: true

module Api
  module Entities
    # S6 / BE-185 — tipo de recebível. Catálogo global.
    class ReceivableKind < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Nome do tipo' }
      expose :integration_key, documentation: { type: 'String', desc: 'Chave de integração' }
      expose :is_active, documentation: { type: 'Boolean', desc: 'Ativo. Sem efeito em filtro (Q-B12)' }
      expose :receivable_entries_count,
             documentation: { type: 'Integer', desc: 'Borderôs vinculados' } do |k, options|
        (options[:usage] || {})[k.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
