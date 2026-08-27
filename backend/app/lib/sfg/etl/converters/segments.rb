# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `segments` (legado) -> `Segment` (ai9). O conversor mais simples do conjunto —
      # está aqui como **exemplo canônico** de quanto código um conversor precisa ter.
      class Segments < Base
        def self.source_table = 'segments'
        def self.target_model = 'Segment'
        def self.owner_slice = 'S4'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        def self.uniques = [%w[title]]

        def convert(row)
          {
            title: row['title'],
            integration_key: row['integration_key'],
            is_active: Values.to_boolean(row['is_active']).value,
            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end
