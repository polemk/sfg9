# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `wallets` (legado) -> `Wallet` (ai9). **S6.**
      #
      # Catálogo pequeno (12 linhas em produção) e já semeado por
      # `Seeds::Reference::Wallets` com o **mesmo `legacy_id`** — que é a chave
      # natural aqui. Rodar o conversor sobre a base semeada **atualiza**, não
      # duplica: é a condição para que a carga não crie uma segunda "Fomento" e
      # deixe metade dos borderôs apontando para cada uma.
      class Wallets < Base
        def self.source_table = 'wallets'
        def self.target_model = 'Wallet'
        def self.owner_slice = 'S6'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            # `strip` porque produção tem `"Boleto Escrow "` com espaço no fim —
            # e o `normalize_catalog_title` do model faria o mesmo. Fazer aqui
            # deixa a reconciliação comparar o que de fato foi gravado.
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
