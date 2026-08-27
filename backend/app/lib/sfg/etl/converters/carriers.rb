# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `carriers` (legado) -> `Carrier` (ai9).
      #
      # O logo NÃO vem por aqui: as 4 colunas Paperclip (`logo_file_name` e as outras
      # três) não são recriadas — o binário é copiado e reanexado por ActiveStorage no
      # passo de anexos (DB-482 / tarefa 6.7), que **depende do disco do servidor
      # legado** e por isso está bloqueado por dependência externa (DEC-84).
      class Carriers < Base
        def self.source_table = 'carriers'
        def self.target_model = 'Carrier'
        def self.owner_slice = 'S4'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        def self.uniques = [%w[bank_code]]
        def self.sums = %w[net_worth]
        # `subordinated_accounts_percent` e DERIVADO no servidor do ai9 (DC-09,
        # `carrier.rb:164-172`: subordinadas x 100 / SENIOR, a formula do legado
        # replicada). Atribui-lo aqui seria escrever um valor que o `before_save`
        # sobrescreve — e a reconciliacao acusaria divergencia em toda linha.
        def self.derived = %w[subordinated_accounts_percent]

        def convert(row)
          {
            title: row['title'],
            resume: row['resume'],
            integration_key: row['integration_key'],
            bank_code: row['bank_code'],
            senior_accounts: row['senior_accounts'],
            subordinated_accounts: row['subordinated_accounts'],
            net_worth: Values.to_decimal(row['net_worth']),
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
