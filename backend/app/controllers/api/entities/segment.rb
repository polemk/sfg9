# frozen_string_literal: true

module Api
  module Entities
    # S3 / BE-075 — segmento. Catálogo global.
    #
    # `projects_count` vem da opção `usage`, calculada **uma vez** pelo endpoint
    # (`CatalogService.usage_counts`) para a página inteira. Calcular aqui dentro
    # seria uma consulta por linha.
    class Segment < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Nome do segmento' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'Chave de integração, congelada na criação (DC-22)' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :projects_count,
             documentation: { type: 'Integer', desc: 'Projetos vinculados — é o que bloqueia a exclusão' } do |s, options|
        (options[:usage] || {})[s.id].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
