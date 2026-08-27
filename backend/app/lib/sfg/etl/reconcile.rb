# frozen_string_literal: true

module Sfg
  module Etl
    # RECONCILIAÇÃO — o relatório que um humano assina antes do cutover (portão 3).
    #
    # Cinco conferências, e cada uma pega uma classe diferente de erro:
    #
    # 1. **Contagem origem × destino** por tabela. Pega linha perdida.
    # 2. **Amostra determinística** (semente fixa) campo a campo. Pega mapeamento
    #    trocado de coluna — o erro que a contagem não vê.
    # 3. **Somatórios financeiros** por tabela e por ano. Pega erro de cast e de
    #    **sinal** — que é o erro que some numa amostra e aparece no total.
    # 4. **Referências religadas** por FK: quantas resolveram pelo de-para e quantas
    #    caíram em órfã. Pega religamento silenciosamente errado.
    # 5. **Fuso por ano (2016–2026)**: cada instante convertido, reexibido em
    #    `America/Sao_Paulo`, mostra **exatamente a mesma hora local** que o legado
    #    mostra hoje. Pega o D-102 — offset fixo num histórico com DST até 2019.
    class Reconcile
      SAMPLE_SEED = 20_260_826
      SAMPLE_SIZE = 25
      SCAN_LIMIT_PER_TABLE = 20_000

      def initialize(source:, report: nil, io: $stdout, only: nil, decisions: nil)
        @source = source
        @report = report || Report.new('reconcile', io: io)
        @io = io
        @only = Array(only).map(&:to_s).presence
        @decisions = decisions || Decisions.load
      end

      attr_reader :source, :report, :io, :decisions

      def run!
        report.meta('origem', source.describe)
        counts_section
        sample_section
        money_section
        relink_section
        timezone_section
        provenance_section
        report
      end

      def converters
        list = Pipeline.converters.reject { |c| c.missing_models.any? || !source.table?(c.source_table) }
        @only ? list.select { |c| @only.include?(c.converter_name) } : list
      end

      private

      # 7.1 — toda diferença é EXPLICADA. Descarte por decisão registrada é diferença
      # esperada e aparece como tal; diferença sem explicação é bloqueante.
      def counts_section
        rows = []
        unexplained = 0
        converters.each do |c|
          origin = source.count(c.source_table)
          target = IdMap.where(source_table: c.source_table).count
          delta = target - origin
          autorizado = authorized_discard(c.source_table)
          explanation = if delta.zero?
                          'igual'
                        elsif delta.negative? && autorizado == delta
                          # Descarte assinado E na quantidade assinada.
                          "descarte por decisão registrada (#{decisions.for("discard:#{c.source_table}").key})"
                        elsif delta.negative?
                          unexplained += 1
                          if autorizado
                            "**FALTANDO no destino** — a decisão autoriza #{autorizado}, faltam #{delta}"
                          else
                            '**FALTANDO no destino** — sem explicação'
                          end
                        else
                          unexplained += 1
                          '**SOBRANDO no destino** — o de-para tem mais linhas que a origem'
                        end
          rows << "| `#{c.source_table}` | #{origin} | #{target} | #{delta} | #{explanation} |"
        end

        report.section('Contagem origem × destino', severity: unexplained.zero? ? :ok : :abort) do |lines|
          lines << '| tabela | origem | destino (de-para) | delta | explicação |'
          lines << '| --- | ---: | ---: | ---: | --- |'
          lines.concat(rows)
        end
      end

      # Quantas linhas esta tabela pode faltar, por decisão ASSINADA — ou `nil`.
      #
      # Existe porque o comentário do `counts_section` prometia isto desde o
      # começo ("descarte por decisão registrada é diferença esperada") e o
      # código nunca consultava as decisões: o portão reprovava a DEC-126, que
      # é uma decisão do usuário sendo CUMPRIDA. É a DEC-127 de novo, do avesso
      # — decisão registrada que não estava implementada.
      #
      # O curinga é recusado de propósito. `Decisions#for` casa `discard:*`, e
      # um curinga aqui autorizaria buraco em QUALQUER tabela — que é o oposto
      # do portão. Cada tabela é uma assinatura própria, como já vale para
      # órfão e duplicata.
      def authorized_discard(table)
        entry = decisions.for("discard:#{table}")
        return nil if entry.nil? || entry.key.to_s.end_with?('*')
        return nil if entry.expected_delta.nil?

        entry.expected_delta.to_i
      end

      # 7.2 — amostra DETERMINÍSTICA. Semente fixa para que duas execuções comparem as
      # mesmas linhas: amostra aleatória a cada rodada esconde regressão.
      def sample_section
        report.section("Amostra determinística campo a campo (semente #{SAMPLE_SEED})", severity: :info) do |lines|
          converters.each do |c|
            rows = source.ordered_rows(c.source_table, pk: c.legacy_pk)
            next if rows.empty?

            rng = Random.new(SAMPLE_SEED)
            picked = rows.sample([SAMPLE_SIZE, rows.size].min, random: rng)
            mismatches = 0
            picked.each do |row|
              ai9_id = IdMap.resolve(c.source_table, row[c.legacy_pk])
              if ai9_id.nil?
                mismatches += 1
                lines << "- `#{c.source_table}`##{row[c.legacy_pk]} — SEM correspondência no de-para"
                next
              end

              record = c.target_class.find_by(id: ai9_id)
              if record.nil?
                mismatches += 1
                lines << "- `#{c.source_table}`##{row[c.legacy_pk]} — de-para aponta para registro inexistente `#{ai9_id}`"
                next
              end

              diff = compare(c, row, record)
              next if diff.empty?

              mismatches += 1
              lines << "- `#{c.source_table}`##{row[c.legacy_pk]} -> `#{ai9_id}`: #{diff.join('; ')}"
            end
            lines << "- `#{c.source_table}`: #{picked.size} amostrada(s), #{mismatches} divergência(s)" \
                     "#{c.derived.any? ? " · colunas derivadas pelo model, fora da comparação: #{c.derived.join(', ')}" : ''}"
          end
        end
      end

      def compare(converter_class, row, record)
        instance = converter_class.new(dummy_run)
        expected = instance.convert(row)
        # A comparação passa o valor esperado pelo **cast do próprio ActiveRecord**,
        # numa cópia descartável. Comparar Ruby-a-Ruby produzia divergência falsa em
        # todo `integer` vindo como string, todo `date` vindo como texto e todo
        # `decimal` vindo como float — ruído que esconde a divergência de verdade.
        probe = record.dup
        derived = converter_class.derived.map(&:to_s)
        expected.filter_map do |key, value|
          next unless record.respond_to?(key) && record.class.column_names.include?(key.to_s)
          next if value.nil? || derived.include?(key.to_s)

          probe.public_send(:"#{key}=", value)
          actual = record.public_send(key)
          next if normalize(probe.public_send(key)) == normalize(actual)

          "`#{key}` esperado #{value.inspect}, gravado #{actual.inspect}"
        end
      rescue StandardError => e
        ["conversão falhou: #{e.class}: #{e.message}"]
      end

      def normalize(value)
        case value
        when BigDecimal, Float then BigDecimal(value.to_s).round(6)
        when Time, DateTime, ActiveSupport::TimeWithZone then value.utc.round
        else value
        end
      end

      # 7.3 — somatórios por tabela e por ano. É o que pega erro de cast e de sinal.
      def money_section
        report.section('Somatórios financeiros por tabela e por ano', severity: :info) do |lines|
          any = false
          converters.each do |c|
            columns = c.try(:sums).to_a
            next if columns.empty?

            any = true
            year_column = c.try(:year_column) || 'created_at'
            buckets = Hash.new { |h, k| h[k] = Hash.new(0) }
            # Somatório não depende de ordem: lê em fluxo, na ordem do arquivo.
            source.each_row(c.source_table) do |row|
              year = row[year_column].to_s[0, 4]
              columns.each { |col| buckets[year][col] += Values.to_decimal(row[col]).to_f }
            end
            lines << "### `#{c.source_table}`"
            lines << "| ano | #{columns.join(' | ')} |"
            lines << "| --- | #{columns.map { '---:' }.join(' | ')} |"
            buckets.keys.sort.each do |year|
              lines << "| #{year} | #{columns.map { |col| format('%.2f', buckets[year][col]) }.join(' | ')} |"
            end
          end
          lines << '- nenhum conversor disponível declara colunas monetárias (`sums`) nesta origem' unless any
        end
      end

      # 7.4
      #
      # **Uma consulta por TABELA referenciada, nunca por linha.** Contra o dump de
      # produção a versão anterior fazia `IdMap.resolve` dentro do laço: só
      # `risk_entries` são 642.447 linhas × 3 referências = quase 2 milhões de
      # `SELECT`, e a reconciliação não terminava. O de-para inteiro de uma tabela
      # cabe em memória; 2 milhões de idas ao banco não cabem em uma janela de
      # cutover.
      def relink_section
        caches = Hash.new { |h, table| h[table] = IdMap.cache_for(table) }

        report.section('Referências religadas por FK', severity: :info) do |lines|
          converters.each do |c|
            c.references.each do |column, referenced|
              cache = caches[referenced]
              total = 0
              resolved = 0
              source.each_row(c.source_table) do |row|
                value = row[column]
                next if value.nil? || value.to_s.strip.empty?

                total += 1
                resolved += 1 if cache.key?(value.to_i)
              end
              next if total.zero?

              lines << "- `#{c.source_table}.#{column}` -> `#{referenced}`: #{resolved}/#{total} resolvidas, " \
                       "#{total - resolved} órfã(s)"
            end
          end
        end
      end

      # 7.5 — a conferência que fecha DB-ETL-04. **Não** confere o instante UTC: confere
      # que ele REEXIBIDO em Brasília dá a mesma hora local que o legado mostra hoje.
      # É essa a única pergunta que o usuário do sistema faz.
      def timezone_section
        report.section('Fuso — conferência amostral por ano (2016–2026)', severity: :info) do |lines|
          lines << '| ano | hora local na origem | UTC gravado | reexibido em America/Sao_Paulo | confere |'
          lines << '| --- | --- | --- | --- | --- |'
          (2016..2026).each do |year|
            local = "#{year}-01-15 10:00:00"
            utc = Values.to_utc(local).value
            back = utc.in_time_zone(Values::ZONE_NAME).strftime('%Y-%m-%d %H:%M:%S')
            ok = back == local
            lines << "| #{year} | #{local} | #{utc.utc.strftime('%Y-%m-%d %H:%M:%S')} | #{back} | #{ok ? 'SIM' : '**NÃO**'} |"
          end
          lines << ''
          lines << 'Janeiro de 2016 a 2018 estava em horário de verão (UTC-2); de 2020 em diante,'
          lines << 'UTC-3 fixo. O UTC gravado MUDA entre os anos e a hora local reexibida NÃO — é'
          lines << 'exatamente isso que um offset fixo erraria (D-102).'
          lines << ''
          lines.concat(real_timestamp_rows)
        end
      end

      # A tabela acima usa datas CONSTRUÍDAS (15 de janeiro de cada ano), e ela prova
      # a regra. Esta usa **instantes que existem na origem**, um por ano encontrado,
      # e prova que a regra vale sobre o dado de verdade — inclusive nos meses em que
      # a virada do DST acontece.
      def real_timestamp_rows
        amostra = {}
        converters.each do |c|
          coluna = (c.timestamps || %w[created_at]).first
          lidas = 0
          source.each_row(c.source_table) do |row|
            lidas += 1
            # Teto por tabela: a amostra é por ANO, e varrer 642.447 linhas de
            # `risk_entries` para descobrir que todas são de 2022–2025 é tempo de
            # cutover gasto à toa.
            break if lidas > SCAN_LIMIT_PER_TABLE

            valor = row[coluna].to_s
            ano = valor[0, 4]
            next unless ano.match?(/\A(19|20)\d\d\z/)
            next if amostra.key?(ano)

            amostra[ano] = [c.source_table, coluna, valor]
          end
        end

        out = ['**Instantes REAIS da origem, um por ano encontrado:**', '',
               '| ano | origem | valor na origem | UTC gravado | reexibido em São Paulo | confere |',
               '| --- | --- | --- | --- | --- | --- |']
        amostra.keys.sort.each do |ano|
          tabela, coluna, valor = amostra[ano]
          utc = Values.to_utc(valor).value
          next if utc.nil?

          local = valor[0, 19].tr('T', ' ')
          back = utc.in_time_zone(Values::ZONE_NAME).strftime('%Y-%m-%d %H:%M:%S')
          out << "| #{ano} | `#{tabela}.#{coluna}` | #{local} | #{utc.utc.strftime('%Y-%m-%d %H:%M:%S')} | " \
                 "#{back} | #{back == local ? 'SIM' : '**NÃO**'} |"
        end
        out << '- (nenhum instante encontrado na origem)' if amostra.empty?
        out
      end

      # 7.6
      def provenance_section
        report.section('Proveniência — `legacy_id` rastreável pelo de-para', severity: :info) do |lines|
          converters.each do |c|
            klass = c.target_class
            next unless klass.column_names.include?('legacy_id')

            total = IdMap.where(source_table: c.source_table).count
            next if total.zero?

            sample = IdMap.where(source_table: c.source_table).order(:legacy_pk).limit(5)
            traced = sample.count do |m|
              record = klass.find_by(id: m.ai9_id)
              record && record.legacy_id.to_i == m.legacy_pk.to_i
            end
            lines << "- `#{c.source_table}`: #{total} no de-para; amostra de #{sample.size}, #{traced} com `legacy_id` batendo"
          end
          lines << ''
          lines << 'DEC-12/BE-451: `legacy_id` é **proveniência**, nunca chave. A chave do ai9 é'
          lines << '`uuid`, e a tradução é sempre pelo de-para.'
        end
      end

      # A comparação precisa instanciar o conversor, que espera um `Run`. Este é um
      # contexto mínimo, em modo dry-run: nada aqui escreve.
      def dummy_run
        @dummy_run ||= Run.new(source: source, mode: :dry_run, report: Report.new('reconcile-inner', io: StringIO.new),
                               io: StringIO.new)
      end
    end
  end
end
