# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `movement_kinds` (legado) -> `MovementKind` (ai9). **S6.**
      #
      # ## Este é o conversor de catálogo mais sensível do bloco de recebíveis
      #
      # São 18 linhas — e são elas que classificam **58.473 tarifas** nos quatro
      # buckets do cálculo. Um `is_desagio` errado aqui muda a base do IOF e os
      # sete CETs de todo borderô daquele tipo.
      #
      # ## `kind` e a conversão de texto pt-BR — tarefa F.2
      #
      # Em produção a coluna guarda `"Crédito"` e `"Débito"`. O de-para é
      # `Values::MOVEMENT_NATURE`, e texto fora dele **não vira `nil` em
      # silêncio**: vira **anomalia no relatório**, linha a linha. É a condição
      # escrita na tarefa F.2 — nenhum texto sem correspondência é convertido
      # sem alguém ver.
      #
      # ## Os quatro classificadores eram `integer` NULLABLE
      #
      # No legado `[nil, 1, nil, nil].sum` levanta `TypeError` — a validação de
      # exclusividade (`movement_kind.rb:12-17`) quebraria com `NULL`. No ai9
      # são `boolean NOT NULL`, e o `Values.to_boolean` reporta todo valor fora
      # de `{0,1}` **antes** de converter.
      class MovementKinds < Base
        def self.source_table = 'movement_kinds'
        def self.target_model = 'MovementKind'
        def self.owner_slice = 'S6'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active is_operation is_title is_advalorem is_desagio is_iof is_liquidation]
        def self.enums = { 'kind' => Values::MOVEMENT_NATURE }
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'].to_s.strip,
            integration_key: row['integration_key'],
            kind: Values.to_enum_key(row['kind'], Values::MOVEMENT_NATURE,
                                     table: self.class.source_table, pk: row['id'], column: 'kind').value,
            is_active: Values.to_boolean(row['is_active']).value,
            is_operation: Values.to_boolean(row['is_operation']).value,
            is_title: Values.to_boolean(row['is_title']).value,
            is_advalorem: Values.to_boolean(row['is_advalorem']).value,
            is_desagio: Values.to_boolean(row['is_desagio']).value,
            is_iof: Values.to_boolean(row['is_iof']).value,
            is_liquidation: Values.to_boolean(row['is_liquidation']).value,
            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Dois classificadores na mesma linha quebrariam o `check_constraint` do
        # banco e, antes disso, a soma dos buckets. Conferido no dump: nenhuma
        # das 18 linhas tem mais de um. O relatório existe para o dia em que
        # tiver.
        def anomalies(row)
          marcados = %w[is_advalorem is_desagio is_iof is_liquidation]
                     .count { |c| Values.to_boolean(row[c]).value }
          return [] if marcados <= 1

          [Values.anomaly_line("#{marcados} classificadores de taxa marcados (BE-447 permite no máximo 1)",
                               self.class.source_table, row['id'], 'is_advalorem/is_desagio/is_iof/is_liquidation',
                               marcados)]
        end
      end
    end
  end
end
