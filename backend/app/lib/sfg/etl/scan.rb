# frozen_string_literal: true

module Sfg
  module Etl
    # A varredura de UMA tabela da origem — é o corpo do `dry-run` (DB-ETL-03).
    #
    # Passa uma vez pelas linhas e conta, por coluna, tudo que a carga precisaria
    # decidir: órfão, duplicata, booleano fora de {0,1}, enum fora do de-para,
    # timestamp ambíguo, truncamento e as anomalias que o próprio conversor declara
    # (é aqui que entra a precedência de papel do Q-16).
    #
    # **Não escreve nada e não corrige nada.** Contagem maior que zero sem decisão
    # registrada **aborta** — a decisão mora em `db/etl/decisions.yml`, versionada e
    # assinada.
    #
    # Roda também na carga: a carga não é cega, ela só não repete o relatório inteiro.
    class Scan
      def initialize(run, converter)
        @run = run
        @converter = converter
        @klass = converter.class
        @orphans = Hash.new { |h, k| h[k] = [] }
        @duplicates = Hash.new { |h, k| h[k] = [] }
        @booleans = Hash.new { |h, k| h[k] = [] }
        @enums = Hash.new { |h, k| h[k] = [] }
        @timestamps = Hash.new { |h, k| h[k] = [] }
        @truncations = Hash.new { |h, k| h[k] = [] }
        @custom = []
        @read = 0
      end

      attr_reader :read

      def orphan_total = @orphans.values.sum(&:size)

      def anomaly_total
        @duplicates.values.sum(&:size) + @booleans.values.sum(&:size) + @enums.values.sum(&:size) +
          @timestamps.values.sum(&:size) + @truncations.values.sum(&:size) + @custom.size
      end

      def run!
        table = @klass.source_table
        seen = Hash.new { |h, k| h[k] = [] }
        timestamp_columns = @klass.timestamps || deduce_timestamp_columns(table)

        @run.source.ordered_rows(table, pk: @klass.legacy_pk).each do |row|
          @read += 1
          pk = row[@klass.legacy_pk]

          check_orphans(row, pk)
          check_booleans(row, pk)
          check_enums(row, pk)
          check_timestamps(row, pk, timestamp_columns)
          check_truncations(row, pk)
          @custom.concat(@converter.anomalies(row))

          @klass.uniques.each do |cols|
            key = cols.map { |c| row[c] }
            next if key.all?(&:nil?)

            seen[[cols, key]] << pk
          end
        end

        seen.each do |(cols, key), pks|
          next if pks.size < 2

          @duplicates[cols.join('+')] << "- `#{cols.join(', ')}` = #{key.inspect} aparece #{pks.size}× (ids: #{pks.first(10).join(', ')})"
        end

        publish!
        self
      end

      private

      def check_orphans(row, pk)
        @klass.references.each do |column, referenced_table|
          value = row[column]
          next if value.nil? || value.to_s.strip.empty?

          pks = @run.source_pks(referenced_table)
          next if pks.nil? # a tabela referenciada não existe nesta origem: não é órfão, é ausência de origem

          next if pks.include?(value.to_i)

          @orphans["#{@klass.source_table}.#{column}"] <<
            "- pk=#{pk} aponta para `#{referenced_table}`##{value}, que não existe na origem"
        end
      end

      def check_booleans(row, pk)
        @klass.booleans.each do |column|
          next unless row.key?(column)

          converted = Values.to_boolean(row[column], table: @klass.source_table, pk: pk, column: column)
          @booleans["#{@klass.source_table}.#{column}"] << converted.anomaly if converted.anomaly?
        end
      end

      def check_enums(row, pk)
        @klass.enums.each do |column, map|
          next unless row.key?(column)

          converted = Values.to_enum_key(row[column], map, table: @klass.source_table, pk: pk, column: column)
          @enums["#{@klass.source_table}.#{column}"] << converted.anomaly if converted.anomaly?
        end
      end

      def check_timestamps(row, pk, columns)
        columns.each do |column|
          next unless row.key?(column)

          converted = Values.to_utc(row[column], table: @klass.source_table, pk: pk, column: column)
          @timestamps["#{@klass.source_table}.#{column}"] << converted.anomaly if converted.anomaly?
        end
      end

      # 5.7 — truncamento. O caso arquetípico é `street_number` (int na origem, string
      # no destino, D-V): o valor "12A" já chegou truncado em "12" no legado, e o ETL
      # não tem como recuperá-lo. Reportar é o único tratamento honesto.
      def check_truncations(row, pk)
        @klass.try(:truncations).to_h.each do |column, note|
          value = row[column]
          next if value.nil? || value.to_s.strip.empty?

          @truncations["#{@klass.source_table}.#{column}"] << "- pk=#{pk} `#{column}` = #{value.inspect} — #{note}"
        end
      end

      def publish!
        @orphans.each do |key, lines|
          @run.record_anomaly_group(key: "orphans:#{key}", title: "Órfãos em `#{key}`", lines: lines)
        end
        @duplicates.each do |key, lines|
          @run.record_anomaly_group(key: "duplicates:#{@klass.source_table}[#{key}]",
                                    title: "Duplicatas em `#{@klass.source_table}` por (#{key}) — o índice único fica BLOQUEADO até resolver",
                                    lines: lines)
        end
        @booleans.each do |key, lines|
          @run.record_anomaly_group(key: "booleans:#{key}", title: "Booleanos fora de {0,1} em `#{key}`", lines: lines)
        end
        @enums.each do |key, lines|
          @run.record_anomaly_group(key: "enums:#{key}", title: "Enum fora do de-para em `#{key}`", lines: lines)
        end
        @timestamps.each do |key, lines|
          @run.record_anomaly_group(key: "timestamps:#{key}", title: "Timestamps ambíguos/inexistentes em `#{key}`",
                                    lines: lines)
        end
        @truncations.each do |key, lines|
          @run.record_anomaly_group(key: "truncations:#{key}", title: "Truncamento em `#{key}`", lines: lines)
        end
        normalized_custom.group_by { |a| a[:key] }.each do |key, items|
          @run.record_anomaly_group(key: key, title: items.first[:title], lines: items.map { |i| i[:line] })
        end
      end

      # `Converter#anomalies` tem DUAS formas em uso, e as duas são legítimas.
      #
      # Achado ao executar contra o dump de produção (26/08/2026): **11 dos 13
      # conversores devolvem STRING** (o retorno de `Values.anomaly_line`) e só 2
      # devolvem o Hash `{key:, title:, line:}`. O `publish!` só sabia ler o Hash e
      # estourava `TypeError: no implicit conversion of Symbol into Integer` na
      # primeira anomalia real — o que a fixture nunca alcançou, porque as duas
      # únicas anomalias que ela dispara vêm justamente dos dois conversores que
      # devolvem Hash.
      #
      # A forma canônica é o Hash (agrupa por chave de decisão própria). A String é
      # aceita e cai numa chave de decisão por conversor. **Nada de exigir que 11
      # conversores de outras fatias mudem**: quem tem o defeito é o leitor.
      def normalized_custom
        default_key = "custom:#{@klass.source_table}"
        default_title = "Anomalias declaradas pelo conversor `#{@klass.converter_name}`"
        @custom.map do |item|
          case item
          when Hash then item
          else { key: default_key, title: default_title, line: item.to_s }
          end
        end
      end

      # DB-073: as colunas de data/hora vêm da introspecção da origem, não de uma
      # lista escrita à mão que envelhece calada.
      def deduce_timestamp_columns(table)
        @run.source.columns(table)
            .select { |c| c[:type].to_s.match?(/timestamp|datetime/i) }
            .map { |c| c[:name] }
      end
    end
  end
end
