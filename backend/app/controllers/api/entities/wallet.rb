# frozen_string_literal: true

module Api
  module Entities
    # S6 / BE-185 — carteira. Catálogo global.
    class Wallet < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Nome da carteira' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'Chave de integração, congelada na criação (DC-22)' }
      expose :is_active,
             documentation: { type: 'Boolean', desc: 'Ativa. NÃO filtra listagem nem select (Q-B12)' }
      expose :receivable_entries_count,
             documentation: { type: 'Integer', desc: 'Borderôs vinculados — é o que bloqueia a exclusão' } do |w, options|
        (options[:usage] || {})[w.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
