# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `receivable_kinds` (legado) -> `ReceivableKind` (ai9). **S6.**
      #
      # 7 linhas em produção, já semeadas com o mesmo `legacy_id`. Ver a nota de
      # idempotência em `Converters::Wallets`.
      class ReceivableKinds < Base
        def self.source_table = 'receivable_kinds'
        def self.target_model = 'ReceivableKind'
        def self.owner_slice = 'S6'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'].to_s.strip,
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
