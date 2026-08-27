# frozen_string_literal: true

module Api
  module Entities
    # **DONA: S8.** Entity de leitura, entregue pela S6 por dependência do
    # formulário de borderô — ver `ResourceSourceService`.
    class ResourceSource < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Nome da fonte' }
      expose :integration_key, documentation: { type: 'String', desc: 'Chave de integração' }
      expose :is_active,
             documentation: { type: 'Boolean', desc: 'Ativa. NÃO filtra o select do borderô (Q-R19)' }
      expose :receivable_entries_count,
             documentation: { type: 'Integer', desc: 'Borderôs vinculados' } do |s, options|
        (options[:usage] || {})[s.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
