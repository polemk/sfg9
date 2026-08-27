# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_operation_types` (legado) -> `RiskOperationType` (ai9). **Escrito pela S5.**
      #
      # ### A carga tem de CASAR com o seed, não duplicá-lo
      #
      # `Seeds::Reference::RiskOperationTypes` já cria as quatro linhas de produção
      # (`fomento`, `comissaria`, `intercompany`, `auto_liquidavel`) — são dado de
      # REFERÊNCIA, sem o qual o sistema não sobe. O ETL carrega **as mesmas
      # linhas** vindas do legado.
      #
      # É por isso que a chave natural é `integration_key`, e não `legacy_id`: as
      # duas fontes convergem para a mesma linha em vez de produzirem duas. A
      # derivação do ai9 (`GlobalCatalog.slugify`) e a do legado
      # (`I18n.transliterate(title).downcase.gsub(" ","_")`) produzem exatamente as
      # mesmas quatro chaves — conferido título a título.
      #
      # ### O `after_create` NÃO pode rodar na carga
      #
      # `RiskOperationType#generate_subtypes!` cria 1 ou 2 subtipos. Se ele rodasse
      # aqui, os subtipos nasceriam **duas vezes**: uma pelo callback e outra pelo
      # conversor `RiskOperationSubtypes`, que carrega os subtipos reais do legado
      # com os ids que as operações apontam. O motor grava por `insert_all`/
      # `upsert_all` (sem callbacks) — este comentário existe para que ninguém
      # "conserte" isso trocando por `create!`.
      #
      # ### `has_pre_faturamento` é o campo de maior risco desta tabela
      #
      # Ele decide se o tipo tem par estático e, portanto, em qual bucket do painel
      # cada operação soma. Carregado como está no legado, sem inferência.
      class RiskOperationTypes < Base
        def self.source_table = 'risk_operation_types'
        def self.target_model = 'RiskOperationType'
        def self.owner_slice = 'S5'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active is_default allow_manual_operations allow_receivable_entries
                               has_pre_faturamento]
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'],
            # A chave do legado é a fonte; se ela vier vazia (linha antiga criada
            # antes do `before_validation`), deriva-se pela MESMA regra.
            integration_key: row['integration_key'].presence || GlobalCatalog.slugify(row['title']),
            is_active: Values.to_boolean(row['is_active']).value,
            is_default: Values.to_boolean(row['is_default']).value,
            allow_manual_operations: Values.to_boolean(row['allow_manual_operations']).value,
            allow_receivable_entries: Values.to_boolean(row['allow_receivable_entries']).value,
            has_pre_faturamento: Values.to_boolean(row['has_pre_faturamento']).value,
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
