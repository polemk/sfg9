# frozen_string_literal: true

module Sfg
  module Etl
    module Source
      # Origem = arquivo `pg_dump` em texto puro.
      #
      # **Por que esta implementação existe e não é um atalho:** no dia em que este
      # motor foi escrito o dump de produção ainda não tinha sido entregue pelo
      # usuário. Um ETL que só roda quando o dump chegar é um ETL que ninguém
      # testou — e o primeiro teste dele seria a janela de cutover.
      #
      # Ela lê o dump **sem banco nenhum**: nada de `psql -f`, nada de base
      # temporária. Serve para introspecção (DB-ETL-01), volumetria (DB-074) e para
      # ler linha, o que já cobre o dry-run inteiro.
      #
      # --------------------------------------------------------------------------
      # DOIS FORMATOS DE DADO, E O DE PRODUÇÃO É O SEGUNDO
      # --------------------------------------------------------------------------
      #
      # `pg_dump` grava dado de duas maneiras, e **a diferença não é cosmética**:
      #
      # * `INSERT INTO … VALUES (…);` — só sai com `--inserts`/`--column-inserts`.
      #   É o formato do dump do sistema Django anterior
      #   (`../sfg/db/seed_assets/sfg_legacy_full.sql`), que era o único disponível
      #   quando esta classe nasceu.
      # * `COPY tabela (cols) FROM stdin;` seguido de linhas separadas por TAB e
      #   terminadas por `\.` — **é o PADRÃO do `pg_dump`, e é o formato do dump de
      #   produção `sfg-31-may-25.sql`** (56 blocos `COPY`, zero `INSERT`).
      #
      # Ler só `INSERT` contra um dump `COPY` **não dá erro**: devolve zero linha em
      # toda tabela, e a volumetria, o dry-run e a reconciliação saem verdes e vazios.
      # Era exatamente esse o estado antes do dump de produção chegar. Os dois
      # formatos são suportados aqui, e a origem informa qual encontrou.
      #
      # --------------------------------------------------------------------------
      # MEMÓRIA — POR QUE O BLOCO `COPY` É LIDO EM FLUXO, E NÃO CARREGADO
      # --------------------------------------------------------------------------
      #
      # O dump de produção tem **782.742 linhas**, das quais **642.447 em
      # `risk_entries`** (25 colunas). Materializar isso como Hash por linha custa
      # gigabytes. A varredura (`parse!`) faz **uma passada** guardando só metadado —
      # esquema, deslocamento em bytes do bloco de cada tabela e a contagem de linhas —
      # e o dado é lido depois, tabela por tabela, direto do arquivo.
      #
      # O único dump versionado no repositório (`sfg_legacy_full.sql`, 8,6 MB) é do
      # **sistema Django anterior** (`SG20210329`) e **não tem tabelas `risk_*`**.
      # Exercita o motor; não é o dump final. O caminho é parametrizado (`DUMP=`).
      class SqlDump < Base
        CREATE_TABLE = /\ACREATE TABLE (?:[\w."]+\.)?(?<table>[\w"]+) \(\z/
        CREATE_INDEX = /\ACREATE (?<unique>UNIQUE )?INDEX (?<name>[\w"]+) ON (?:[\w."]+\.)?(?<table>[\w"]+) USING \w+ \((?<cols>[^)]*)\)/
        INSERT_HEAD  = /\AINSERT INTO (?:[\w."]+\.)?(?<table>[\w"]+)(?: \((?<cols>[^)]*)\))? VALUES /
        COPY_HEAD    = /\ACOPY (?:[\w."]+\.)?(?<table>[\w"]+) \((?<cols>[^)]*)\) FROM stdin;\z/
        ADD_UNIQUE   = /\A\s*ADD CONSTRAINT (?<name>[\w"]+) (?<kind>PRIMARY KEY|UNIQUE) \((?<cols>[^)]*)\)/

        # Sequências de escape do formato TEXT do `COPY` (o inverso do que o
        # Postgres grava). `\N` é NULL e **não** é a string "N".
        COPY_ESCAPES = { 'N' => nil, 'n' => "\n", 't' => "\t", 'r' => "\r",
                         'b' => "\b", 'f' => "\f", 'v' => "\v", '\\' => '\\' }.freeze

        def initialize(path)
          super()
          @path = Pathname.new(path.to_s)
          raise UnavailableSource, "dump nao encontrado: #{@path}" unless @path.exist?

          @schema = nil
          @inline_rows = nil
          @copy_index = nil
        end

        attr_reader :path

        def describe
          parse!
          "dump #{path} (#{(path.size / 1_048_576.0).round(1)} MB, formato #{format_name}, " \
            "#{tables.size} tabela(s), #{tables.sum { |t| count(t) }} linha(s))"
        end

        # `copy`, `insert` ou `vazio` — entra no cabeçalho de todo relatório, porque
        # "formato insert contra dump copy" é um modo de falha silencioso.
        def format_name
          parse!
          return 'copy' if @copy_index.any?
          return 'insert' if @inline_rows.any?

          'vazio (nenhum INSERT e nenhum COPY)'
        end

        def tables = schema.keys.sort
        def columns(table) = schema.fetch(table.to_s, { columns: [] })[:columns]
        def indexes(table) = schema.fetch(table.to_s, { indexes: [] })[:indexes]

        def count(table)
          parse!
          entry = @copy_index[table.to_s]
          return entry[:count] if entry

          @inline_rows.fetch(table.to_s, []).size
        end

        # Conjunto de PKs da tabela, **sem materializar linha nenhuma**. É o que a
        # contagem de órfãos consome: com `risk_entries` na origem, montar o conjunto
        # a partir de 642.447 Hashes custaria minutos e um gigabyte à toa.
        def pks(table, pk: 'id')
          parse!
          entry = @copy_index[table.to_s]
          unless entry
            return @inline_rows.fetch(table.to_s, []).filter_map { |r| r[pk]&.to_i }.to_set
          end

          index = entry[:columns].index(pk)
          return Set.new if index.nil?

          set = Set.new
          each_raw_line(entry) { |line| set << split_copy_line(line)[index].to_i }
          set
        end

        # Linhas na ordem do ARQUIVO (ordem de heap do Postgres), em fluxo. Uma linha
        # viva por vez.
        def each_row(table)
          return enum_for(:each_row, table) unless block_given?

          parse!
          entry = @copy_index[table.to_s]
          unless entry
            @inline_rows.fetch(table.to_s, []).each { |r| yield r }
            return
          end

          names = entry[:columns]
          casts = entry[:casts]
          each_raw_line(entry) { |line| yield build_row(names, casts, split_copy_line(line)) }
        end

        # Linhas ordenadas pela PK. **Ordem estável entre execuções é o que faz a
        # retomada chegar ao mesmo estado final** — e o `COPY` do dump de produção
        # NÃO vem ordenado por PK (medido: 24 das 56 tabelas saem fora de ordem).
        #
        # Devolve um `Enumerable` preguiçoso: guarda as linhas CRUAS (string) e a
        # ordem, e só monta o Hash da linha que está sendo consumida.
        def ordered_rows(table, pk: 'id')
          parse!
          entry = @copy_index[table.to_s]
          unless entry
            list = @inline_rows.fetch(table.to_s, [])
            return list unless list.first&.key?(pk)

            return list.sort_by { |r| r[pk].to_i }
          end

          SortedRows.new(self, entry, pk)
        end

        # Lotes já ordenados, sem passar por `Array#select` (que materializaria a
        # tabela inteira só para descartar o que já foi carregado).
        def each_batch(table, pk: 'id', batch_size: 1_000, after_pk: nil)
          rows = ordered_rows(table, pk: pk)
          enum = after_pk ? rows.lazy.select { |r| r[pk].to_i > after_pk.to_i } : rows.each_entry
          enum.each_slice(batch_size) { |slice| yield slice }
        end

        # ------------------------------------------------------------------
        # Parsing — uma passada só pelo arquivo, guardando ESTRUTURA e ÍNDICE.
        # ------------------------------------------------------------------
        def schema
          parse!
          @schema
        end

        # Só o dump em formato `INSERT` guarda linha em memória.
        def rows
          parse!
          @inline_rows
        end

        def copy_index
          parse!
          @copy_index
        end

        # Lê as linhas cruas de um bloco `COPY`, a partir do deslocamento gravado.
        def each_raw_line(entry)
          File.open(path, 'r:UTF-8') do |io|
            io.seek(entry[:offset])
            while (line = io.gets)
              line = line.chomp("\n")
              break if line == '\\.'

              yield line
            end
          end
        end

        def split_copy_line(line)
          line.split("\t", -1).map { |field| decode_copy(field) }
        end

        def build_row(names, casts, values)
          row = {}
          names.each_with_index do |name, i|
            raw = values[i]
            row[name] = casts[i] == :boolean ? decode_boolean(raw) : raw
          end
          row
        end

        private

        def parse!
          return @schema unless @schema.nil?

          @schema = {}
          @inline_rows = Hash.new { |h, k| h[k] = [] }
          @copy_index = {}
          state = nil
          current = nil
          buffer = +''
          offset = 0

          File.open(path, 'r:UTF-8') do |io|
            while (raw = io.gets)
              offset += raw.bytesize
              line = raw.chomp("\n")

              case state
              when :table
                if line.start_with?(');')
                  state = nil
                else
                  col = parse_column(line)
                  @schema[current][:columns] << col if col
                end
                next
              when :copy
                if line == '\\.'
                  state = nil
                  current = nil
                else
                  @copy_index[current][:count] += 1
                end
                next
              when :insert
                buffer << "\n" << line
                next unless buffer.rstrip.end_with?(');')

                absorb_insert(buffer)
                buffer = +''
                state = nil
                next
              when :alter
                state = nil if line.end_with?(';')
                absorb_constraint(current, line)
                next
              end

              if (m = CREATE_TABLE.match(line))
                current = unquote(m[:table])
                @schema[current] = { columns: [], indexes: [] }
                state = :table
              elsif (m = COPY_HEAD.match(line))
                current = unquote(m[:table])
                ensure_table(current)
                @copy_index[current] = { table: current, offset: offset, count: 0,
                                         columns: m[:cols].split(',').map { |c| unquote(c.strip) } }
                state = :copy
              elsif (m = CREATE_INDEX.match(line))
                table = unquote(m[:table])
                ensure_table(table)
                @schema[table][:indexes] << {
                  name: unquote(m[:name]),
                  columns: m[:cols].split(',').map { |c| unquote(c.strip.split(/\s/).first) },
                  unique: !m[:unique].nil?
                }
              elsif line.start_with?('ALTER TABLE ONLY ') && !line.end_with?(';')
                current = unquote(line.sub('ALTER TABLE ONLY ', '').strip.split('.').last)
                state = :alter
              elsif line.start_with?('INSERT INTO ')
                if line.rstrip.end_with?(');')
                  absorb_insert(line)
                else
                  buffer = +line.dup
                  state = :insert
                end
              end
            end
          end

          @schema.each_value { |t| t[:columns].freeze }
          @copy_index.each_value { |e| e[:casts] = cast_plan(e) }
          @schema
        end

        # O tipo declarado no `CREATE TABLE` é o que diz como ler o campo do `COPY`.
        # No dump de produção existe **um único** `boolean`
        # (`livetat_auth_users.deactivated`) — todo o resto é `integer` 0/1, que é
        # exatamente a regra D-E. Ler `t`/`f` como string faria o conversor de
        # booleano contar 135 anomalias inexistentes.
        def cast_plan(entry)
          types = @schema.fetch(entry[:table], { columns: [] })[:columns]
                         .to_h { |c| [c[:name], c[:type].to_s] }
          entry[:columns].map { |name| types[name].to_s.start_with?('boolean') ? :boolean : :text }
        end

        def decode_boolean(raw)
          case raw
          when 't' then true
          when 'f' then false
          else raw
          end
        end

        # Formato TEXT do `COPY`: campo vazio é string vazia, `\N` é NULL.
        def decode_copy(field)
          return nil if field == '\\N'
          return field unless field.include?('\\')

          out = +''
          i = 0
          while i < field.length
            ch = field[i]
            if ch == '\\'
              nxt = field[i + 1]
              if COPY_ESCAPES.key?(nxt)
                mapped = COPY_ESCAPES[nxt]
                out << (mapped || '\\N')
                i += 2
                next
              end
              out << nxt.to_s
              i += 2
              next
            end
            out << ch
            i += 1
          end
          out
        end

        def ensure_table(table)
          @schema[table] ||= { columns: [], indexes: [] }
        end

        # `ADD CONSTRAINT foo_pkey PRIMARY KEY (id);` também é índice único, e sem
        # isto a introspecção reporta "0 índices" em tabela que tem chave primária.
        def absorb_constraint(table, line)
          return if table.nil?

          m = ADD_UNIQUE.match(line)
          return if m.nil?

          ensure_table(table)
          @schema[table][:indexes] << {
            name: unquote(m[:name]),
            columns: m[:cols].split(',').map { |c| unquote(c.strip) },
            unique: true,
            primary: m[:kind] == 'PRIMARY KEY'
          }
        end

        # `    id integer NOT NULL,` -> { name: 'id', type: 'integer', null: false }
        def parse_column(line)
          text = line.strip.sub(/,\z/, '')
          return nil if text.empty? || text.start_with?('CONSTRAINT', '--')

          name = unquote(text[/\A("[^"]+"|\S+)/, 1])
          rest = text.sub(/\A("[^"]+"|\S+)/, '').strip
          type = rest[/\A[a-zA-Z][\w ]*(?:\([^)]*\))?(?:\[\])?/].to_s.strip
          { name: name, type: type, null: !rest.include?('NOT NULL'),
            default: rest[/DEFAULT (.+?)(?: NOT NULL)?\z/, 1] }
        end

        def absorb_insert(statement)
          m = INSERT_HEAD.match(statement)
          return unless m

          table = unquote(m[:table])
          values_text = statement[m.end(0)..].to_s.strip.sub(/;\z/, '')
          values_text = values_text[1..-2].to_s if values_text.start_with?('(')
          names = if m[:cols]
                    m[:cols].split(',').map { |c| unquote(c.strip) }
                  else
                    ensure_table(table)[:columns].map { |c| c[:name] }
                  end
          @inline_rows[table] << names.zip(split_values(values_text)).to_h
        end

        # Tokenizador de lista SQL. Precisa existir porque `split(',')` quebra em
        # `'Silva, Joao'` — e uma virgula dentro de um nome desloca TODAS as colunas
        # daquela linha em silencio, que e o pior modo de falha possivel num ETL.
        #
        # Devolve `[valor]` ja tipado: string entre aspas continua string (inclusive
        # a vazia), `NULL` vira `nil`, `true`/`false` viram booleano.
        def split_values(text)
          out = []
          buf = +''
          quoted = false
          in_string = false
          i = 0
          while i < text.length
            ch = text[i]
            if in_string
              if ch == "'"
                if text[i + 1] == "'"
                  buf << "'"
                  i += 2
                  next
                end
                in_string = false
              else
                buf << ch
              end
            elsif ch == "'"
              # O espaço que separa `…, 'valor'` NÃO faz parte do valor. Sem esta
              # linha toda coluna depois da primeira num dump em formato `INSERT`
              # voltava com um espaço à esquerda (`" Outro"`).
              buf = +'' if buf.strip.empty?
              in_string = true
              quoted = true
            elsif ch == ','
              out << finish_value(buf, quoted)
              buf = +''
              quoted = false
            else
              buf << ch
            end
            i += 1
          end
          out << finish_value(buf, quoted)
          out
        end

        def finish_value(buf, quoted)
          return buf if quoted

          case buf.strip
          when 'NULL', '' then nil
          when 'true' then true
          when 'false' then false
          else buf.strip
          end
        end

        def unquote(value) = value.to_s.delete('"')

        # ------------------------------------------------------------------
        # Linhas de um bloco `COPY`, ordenadas pela PK, montadas uma por vez.
        #
        # Guarda as linhas **cruas** (uma String por linha) e uma permutação de
        # índices. Para `risk_entries` isso é ~150 MB de string contra os ~1,5 GB que
        # 642.447 Hashes de 25 chaves custariam — e só um Hash vive por vez.
        # ------------------------------------------------------------------
        class SortedRows
          include Enumerable

          def initialize(dump, entry, pk)
            @dump = dump
            @entry = entry
            @pk = pk
          end

          def size = @entry[:count]
          alias length size
          def empty? = size.zero?

          # `Enumerable#to_a.sample` materializaria a tabela inteira para tirar 25
          # linhas — 642.447 Hashes em `risk_entries`. Aqui sorteiam-se as POSIÇÕES e
          # só elas viram Hash.
          def sample(n, random: Random.new)
            raws = []
            @dump.each_raw_line(@entry) { |line| raws << line }
            posicoes = (0...raws.size).to_a.sample([n, raws.size].min, random: random)
            posicoes.map { |i| @dump.build_row(@entry[:columns], @entry[:casts], @dump.split_copy_line(raws[i])) }
          end

          def each
            return enum_for(:each) unless block_given?

            names = @entry[:columns]
            casts = @entry[:casts]
            index = names.index(@pk)

            raws = []
            @dump.each_raw_line(@entry) { |line| raws << line }

            order = if index.nil?
                      (0...raws.size).to_a
                    else
                      (0...raws.size).sort_by { |i| @dump.split_copy_line(raws[i])[index].to_i }
                    end

            order.each { |i| yield @dump.build_row(names, casts, @dump.split_copy_line(raws[i])) }
            self
          end
        end
      end
    end
  end
end
