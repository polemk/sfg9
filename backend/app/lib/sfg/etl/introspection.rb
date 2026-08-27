# frozen_string_literal: true

module Sfg
  module Etl
    # DB-ETL-01 + DB-073 + DB-074 — a etapa que troca **surpresa no cutover** por
    # **surpresa no dry-run**.
    #
    # Três coisas, nesta ordem, e as três viram seção do relatório em arquivo:
    #
    # 1. **Esquema real da origem** (tabelas, colunas, tipos, índices), lido da própria
    #    origem. Nenhuma coluna usada pelo ETL é suposta — DB-073.
    # 2. **Volumetria** por tabela — DB-074. É a linha de base da reconciliação.
    # 3. **Comparação com o esperado** das 139 migrations. Tabela, coluna ou índice
    #    desconhecido **ABORTA**, nomeando o que encontrou. As duas divergências já
    #    conhecidas (`availability_templates.default_position`, D-06, e
    #    `contracts.description`, D-108) estão na allowlist e **não** abortam; uma
    #    terceira aborta.
    class Introspection
      def initialize(source, report: nil, baseline: nil)
        @source = source
        @report = report || Report.new('introspect')
        @baseline = baseline
      end

      attr_reader :source, :report

      def run!
        report.meta('origem', source.describe)
        schema_section
        volumetry_section
        coverage_section
        comparison_section
        report
      end

      def baseline
        @baseline ||= LegacySchema.load_baseline
      rescue StandardError => e
        @baseline_error = e.message
        nil
      end

      # ---------------------------------------------------------------- seções

      def schema_section
        report.section("Esquema real da origem — #{source.tables.size} tabela(s)", severity: :info) do |lines|
          source.tables.each do |table|
            cols = source.columns(table)
            idx = source.indexes(table)
            lines << "### `#{table}` — #{cols.size} coluna(s), #{idx.size} índice(s)"
            cols.each { |c| lines << "  - `#{c[:name]}` #{c[:type]}#{c[:null] ? '' : ' NOT NULL'}" }
            idx.each do |i|
              lines << "  - índice #{i[:unique] ? 'ÚNICO ' : ''}`#{i[:name]}` (#{Array(i[:columns]).join(', ')})"
            end
          end
        end
      end

      # DB-074. Produzido ANTES da carga e comparado DEPOIS dela — é a linha de base
      # que `sfg_etl:reconcile` usa.
      def volumetry
        @volumetry ||= source.tables.to_h { |t| [t, source.count(t)] }
      end

      def volumetry_section
        total = volumetry.values.sum
        report.section("Volumetria — #{total} linha(s) em #{volumetry.size} tabela(s)", severity: :info) do |lines|
          lines << '| tabela | linhas |'
          lines << '| --- | ---: |'
          volumetry.sort_by { |t, n| [-n, t] }.each { |t, n| lines << "| `#{t}` | #{n} |" }
        end
        volumetry
      end

      # COBERTURA — a pergunta que a volumetria sozinha não responde: **existe tabela
      # com dado em produção que nenhum conversor reivindica e nenhum descarte
      # explica?**
      #
      # Sem esta seção, "nada foi perdido" é uma afirmação sobre a soma dos
      # relatórios de cada conversor, e a lição do Phase 1 é que a verificação se faz
      # no consolidado: cinco agentes reportaram cobertura completa dentro da própria
      # fatia e havia 31 IDs órfãos nas fronteiras.
      def coverage_section
        claimed = Pipeline.converters.flat_map { |c| [c.source_table, *c.also_reads] }.to_set
        declared_drops = Pipeline.do_not_migrate
        infrastructure = LegacySchema::INFRASTRUCTURE_TABLES - claimed.to_a

        gaps = source.tables.reject do |table|
          claimed.include?(table) || declared_drops.key?(table) ||
            infrastructure.include?(table) || source.count(table).zero?
        end

        report.section("Tabelas com dado e SEM dono declarado — #{gaps.size}",
                       severity: gaps.empty? ? :ok : :warn) do |lines|
          lines << 'Uma tabela da origem precisa estar num de três lugares: na ordem de carga'
          lines << '(`db/etl/load_order.yml`), na lista `do_not_migrate` com motivo, ou na lista de'
          lines << 'infraestrutura. Fora disso é dado de produção que ninguém reivindicou.'
          lines << ''
          if gaps.empty?
            lines << '- nenhuma. Toda tabela com linha tem conversor ou descarte com motivo.'
          else
            gaps.sort_by { |t| -source.count(t) }.each { |t| lines << "- `#{t}` — #{source.count(t)} linha(s)" }
          end
          lines << ''
          lines << 'Descartes declarados que **têm linha** na origem (a contagem entra no relatório'
          lines << 'antes de o descarte fechar):'
          com_linha = declared_drops.keys.select { |t| source.table?(t) && source.count(t).positive? }
          if com_linha.empty?
            lines << '- nenhum: todo descarte declarado tem 0 linha em produção'
          else
            com_linha.sort.each do |t|
              lines << "- `#{t}` — #{source.count(t)} linha(s) · #{declared_drops[t].to_s.squish}"
            end
          end
        end
      end

      def comparison_section
        expected = baseline
        if expected.nil?
          report.section('Comparação com o esperado — NÃO EXECUTADA', severity: :warn) do |lines|
            lines << "Baseline indisponível: #{@baseline_error}"
            lines << 'Rode `rake sfg_etl:baseline SFG_LEGACY_ROOT=../sfg` para gerar.'
          end
          return
        end

        expected_tables = expected.fetch('tables', {})
        unknown_tables = source.tables - expected_tables.keys - LegacySchema::INFRASTRUCTURE_TABLES -
                         LegacySchema::REFERENCE_ONLY_TABLES
        missing_tables = expected_tables.keys - source.tables - LegacySchema::INFRASTRUCTURE_TABLES -
                         LegacySchema::REFERENCE_ONLY_TABLES

        unknown_columns = []
        missing_columns = []
        (source.tables & expected_tables.keys).each do |table|
          have = source.column_names(table)
          want = expected_tables.dig(table, 'columns').to_a.map { |c| c['name'] }
          allowed = LegacySchema::KNOWN_EXTRA_COLUMNS.fetch(table, [])
          (have - want - allowed).each { |c| unknown_columns << "#{table}.#{c}" }
          (want - have).each { |c| missing_columns << "#{table}.#{c}" }
        end

        report_known_divergences(source.tables, expected_tables)

        # Faltar é aviso (a migration pode ter sido revertida à mão na origem);
        # sobrar é ABORTO (é dado que o ETL não sabe converter e perderia calado).
        report.section("Colunas/tabelas do esperado ausentes na origem — #{missing_tables.size + missing_columns.size}",
                       severity: missing_tables.empty? && missing_columns.empty? ? :ok : :warn) do |lines|
          missing_tables.sort.each { |t| lines << "- tabela `#{t}` declarada por migration e ausente na origem" }
          missing_columns.sort.each { |c| lines << "- coluna `#{c}` declarada por migration e ausente na origem" }
        end

        surprises = unknown_tables.sort.map { |t| "- **tabela desconhecida** `#{t}` (#{source.count(t)} linha(s))" } +
                    unknown_columns.sort.map { |c| "- **coluna desconhecida** `#{c}`" }

        report.section("Surpresas na origem — #{surprises.size}", severity: surprises.empty? ? :ok : :abort) do |lines|
          if surprises.empty?
            lines << 'Nenhuma. O esquema real da origem cabe no esperado das migrations.'
          else
            lines.concat(surprises)
            lines << ''
            lines << '**O ETL não converte o que não conhece.** Cada linha acima precisa de uma'
            lines << 'de duas decisões, registrada antes do cutover: mapear (vira conversor) ou'
            lines << 'descartar (vira linha em `removed-features.md`, com evidência).'
          end
        end
      end

      def report_known_divergences(source_tables, expected_tables)
        found = []
        LegacySchema::KNOWN_EXTRA_COLUMNS.each do |table, columns|
          next unless source_tables.include?(table)

          have = source.column_names(table)
          want = expected_tables.dig(table, 'columns').to_a.map { |c| c['name'] }
          columns.each { |c| found << "#{table}.#{c}" if have.include?(c) && !want.include?(c) }
        end

        report.section('Divergências CONHECIDAS (não abortam)', severity: :info) do |lines|
          lines << '`availability_templates.default_position` (D-06/D-125) e `contracts.description`'
          lines << '(D-108) eram as duas supostas provas de "esquema editado fora das migrations".'
          lines << ''
          lines << '**Medido contra o dump de produção de 31/05/2025: NENHUMA DAS DUAS EXISTE.**'
          lines << '`default_position` aparece ZERO vez no dump inteiro, e `contracts` tem 7 colunas'
          lines << 'e nenhuma `description` — o `description` do contrato é `has_rich_text`'
          lines << '(`contract.rb:11`), ou seja ActionText, e vive em `action_text_rich_texts`.'
          lines << ''
          lines << '- **D-108 muda de veredito:** não é schema fora do versionamento, é ActionText.'
          lines << '- **D-06/D-125 continua defeito:** `order!(default_position: :asc)` emite'
          lines << '  `ORDER BY default_position` contra coluna que não existe.'
          lines << ''
          lines << 'A allowlist FICA. Ela não descreve o que existe: descreve o que, se aparecer,'
          lines << 'não deve abortar. **Uma terceira surpresa aborta** — e é assim que os 7 falsos'
          lines << 'positivos do baseline incompleto foram pegos em 26/08/2026.'
          lines << ''
          lines << (if found.empty?
                      '- nenhuma delas presente nesta origem (é o resultado esperado contra produção)'
                    else
                      found.map { |f| "- presente nesta origem: `#{f}`" }.join("\n")
                    end)
        end
      end
    end
  end
end
