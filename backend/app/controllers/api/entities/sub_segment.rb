# frozen_string_literal: true

module Api
  module Entities
    # S3 / BE-077 — subsegmento. Catálogo global e INDEPENDENTE de `segments` (DC-13).
    class SubSegment < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Nome do subsegmento' }
      expose :integration_key, documentation: { type: 'String' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :projects_count, documentation: { type: 'Integer' } do |s, options|
        (options[:usage] || {})[s.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
