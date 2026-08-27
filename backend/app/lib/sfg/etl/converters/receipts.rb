# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `receipts` (legado) -> `Receipt` (ai9). **S6**, **DB-163**, **DB-164**.
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM — igual a `charges`
      #
      # `20220802225011_create_receipts` e `20220804195335_add_date_and_operation_title_to_receipts`
      # nunca subiram; `remunerations` também não. Zero linhas lidas é o
      # resultado esperado. Ver a nota completa em `Converters::Charges`.
      #
      # ## A referência polimórfica é religada por DUAS tabelas de de-para
      #
      # `operation_id` aponta ora para `risk_operations`, ora para
      # `structured_operations`, e o `operation_type` diz qual. O motor religa
      # **exclusivamente pelo de-para**, então a escolha da tabela é feita aqui,
      # linha a linha — não dá para declarar em `references`, que é estático.
      #
      # Tipo desconhecido **não vira `nil` em silêncio**: vira anomalia. No
      # legado o `else` de `Remuneration#beauty_type` devolvia a string `"???"`,
      # que passava pela validação de presença e virava um recibo que nenhum
      # filtro encontrava.
      class Receipts < Base
        def self.source_table = 'receipts'
        def self.target_model = 'Receipt'
        def self.owner_slice = 'S6'

        def self.references
          {
            'project_id' => 'projects',
            'charge_id' => 'charges',
            'remuneration_id' => 'remunerations',
            'user_id' => 'livetat_auth_users'
          }
        end

        def self.sums = %w[value operation_value]
        def self.year_column = 'date'

        OPERATION_TABLES = {
          'RiskOperation' => 'risk_operations',
          'StructuredOperation' => 'structured_operations'
        }.freeze

        def convert(row)
          tabela = OPERATION_TABLES[row['operation_type'].to_s]

          {
            project_id: ref('projects', row['project_id']),
            charge_id: ref('charges', row['charge_id']),
            remuneration_id: ref('remunerations', row['remuneration_id']),
            user_id: ref('livetat_auth_users', row['user_id']),
            operation_type: row['operation_type'],
            operation_id: tabela ? ref(tabela, row['operation_id']) : nil,
            temp_id: row['temp_id'],
            kind: row['kind'],
            title: row['title'],
            fee: Values.to_decimal(row['fee']),
            operation_value: Values.to_decimal(row['operation_value']),
            # D-B14 — a receita faturada, COPIADA. Recalcular
            # `operation_value × (fee/100)` aqui substituiria o número emitido
            # por um número gerado (mesmo critério do borderô).
            value: Values.to_decimal(row['value']),
            date: row['date'],
            operation_title: row['operation_title'],
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          linhas = []
          unless OPERATION_TABLES.key?(row['operation_type'].to_s)
            linhas << Values.anomaly_line(
              "tipo de operação desconhecido: #{row['operation_type'].inspect}. No legado isto virava a " \
              'string "???" e o recibo ficava invisível a qualquer filtro.',
              self.class.source_table, row['id'], 'operation_type', row['operation_type']
            )
          end
          unless %w[LIQ EST].include?(row['kind'].to_s)
            linhas << Values.anomaly_line(
              "sigla de tipo fora de {LIQ, EST}: #{row['kind'].inspect}",
              self.class.source_table, row['id'], 'kind', row['kind']
            )
          end
          linhas
        end
      end
    end
  end
end
