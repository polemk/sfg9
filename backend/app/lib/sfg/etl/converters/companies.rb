# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `companies` (legado) -> `Company` (ai9).
      #
      # **BE-452 (b)** vive aqui: no ETL de 2021 a empresa dos recebiveis era forcada
      # para um identificador fixo "por questao de portabilidade". Sao registros de
      # producao com empresa errada por construcao — o dry-run conta, nao corrige.
      class Companies < Base
        def self.source_table = 'companies'
        def self.target_model = 'Company'
        def self.owner_slice = 'S4'
        def self.references = { 'project_id' => 'projects' }
        def self.uniques = [%w[project_id title]]
        # `has_safegold_management` e `integer` na origem (D-30) — como em
        # `receivable_entries` e `renegotiations`.
        def self.booleans = %w[has_safegold_management]

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            title: row['title'],
            # DEC-112 — CARIMBO histórico, vindo da origem. Ver `SafegoldStamped`.
            has_safegold_management: Values.to_boolean(row['has_safegold_management']).value,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end
