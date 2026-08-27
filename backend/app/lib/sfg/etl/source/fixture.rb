# frozen_string_literal: true

module Sfg
  module Etl
    module Source
      # Origem = dado VERSIONADO com a forma do legado, em `db/etl/fixtures/`.
      #
      # **Para que serve:** exercitar o motor inteiro — lote, transação, checkpoint,
      # retomada, idempotência, religamento de FK, órfão, duplicata, anomalia — sem
      # depender do dump de produção, que é dependência externa do usuário.
      #
      # As linhas foram escolhidas para conter, de propósito, **cada uma das anomalias
      # que o dry-run tem de pegar**: um órfão, uma duplicata, um booleano fora de
      # {0,1}, um papel vazio, um usuário com `username` e nenhum canal, uma conta
      # inativa e um caso de precedência invertida do Q-16. Um dry-run que sai limpo
      # contra esta fixture está quebrado.
      #
      # Os e-mails usam o domínio reservado `.invalid` (RFC 2606) e o prefixo
      # `etl-fixture-`, para que nada disto se confunda com dado de demo ou de gente.
      class Fixture < Base
        DIR = 'db/etl/fixtures'

        def initialize(dir = nil)
          super()
          @dir = Pathname.new(dir || Rails.root.join(DIR))
          raise UnavailableSource, "fixtures nao encontradas: #{@dir}" unless @dir.directory?
        end

        def describe = "fixture #{@dir} (#{tables.size} tabela(s), #{tables.sum { |t| count(t) }} linha(s))"

        def tables = data.keys.sort
        def count(table) = data.fetch(table.to_s, []).size

        def columns(table)
          rows = data.fetch(table.to_s, [])
          return [] if rows.empty?

          names = rows.flat_map(&:keys).uniq
          names.map { |n| { name: n, type: baseline_type(table, n), null: true, default: nil } }
        end

        def ordered_rows(table, pk: 'id')
          rows = data.fetch(table.to_s, [])
          rows.first&.key?(pk) ? rows.sort_by { |r| r[pk].to_i } : rows
        end

        private

        def data
          @data ||= Dir[@dir.join('*.yml')].sort.to_h do |file|
            raw = YAML.safe_load_file(file, permitted_classes: [Date, Time]) || {}
            [raw.fetch('table', File.basename(file, '.yml')),
             Array(raw['rows']).map { |r| r.transform_keys(&:to_s) }]
          end
        end

        def baseline_type(table, column)
          @baseline ||= begin
            LegacySchema.load_baseline.fetch('tables', {})
          rescue StandardError
            {}
          end
          @baseline.dig(table.to_s, 'columns')&.find { |c| c['name'] == column }&.fetch('type', 'unknown') || 'unknown'
        end
      end
    end
  end
end
