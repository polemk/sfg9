# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `project_indicator_connections` (legado) -> `ProjectIndicatorConnection`. S10.
      #
      # Junção pura. Duas notas:
      #
      # **1. `is_active` não é convertida porque NÃO EXISTE na origem.** O
      # `project_indicator_connections_controller.rb:196` do legado a aceita no
      # `permit` e a coluna nunca foi criada — o parâmetro é descartado em silêncio
      # desde 2021. Quem for procurá-la na origem não vai achar, e é isso mesmo.
      #
      # **2. A unicidade (`project_id`, `indicator_id`) só existia em
      # `validates_uniqueness_of`**, sem índice no banco: **há corrida** e pode
      # haver par duplicado na origem. Declarada em `uniques` para que o motor
      # conte antes de o índice único do ai9 recusar a carga no meio.
      class ProjectIndicatorConnections < Base
        def self.source_table = 'project_indicator_connections'
        def self.target_model = 'ProjectIndicatorConnection'
        def self.owner_slice = 'S10'
        def self.references = { 'project_id' => 'projects', 'indicator_id' => 'indicators' }
        def self.uniques = [%w[project_id indicator_id]]

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            indicator_id: ref('indicators', row['indicator_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end
