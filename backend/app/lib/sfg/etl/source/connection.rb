# frozen_string_literal: true

module Sfg
  module Etl
    module Source
      # Origem = banco vivo do legado, por URL.
      #
      # **É esta a origem do cutover** — e é a que está **BLOQUEADA POR DEPENDÊNCIA
      # EXTERNA**: o acesso (ou o dump) do banco de produção do Safegold só o usuário
      # consegue obter. Nada aqui supõe formato: tudo vem do `information_schema`,
      # que é a exigência de DB-073 ("nenhuma coluna usada pelo ETL é suposta").
      #
      # Conexão **somente leitura por construção**: `establish_connection` num pool
      # próprio e nenhum método de escrita neste arquivo. O usuário deve ainda assim
      # entregar credencial de leitura — e **rotacionar** a que está em texto puro no
      # legado (`database.linux.yml:8,25`), item 9.11 do runbook.
      class Connection < Base
        POOL_NAME = 'SfgLegacySource'

        def initialize(url)
          super()
          @url = url.to_s
          raise UnavailableSource, 'SFG_LEGACY_URL nao definida' if @url.empty?

          @pool = build_pool
        end

        def describe = "banco legado #{@url.sub(%r{//[^@]*@}, '//***@')}"

        def tables
          @tables ||= with_conn { |c| c.tables.sort }
        end

        def columns(table)
          with_conn do |c|
            c.columns(table.to_s).map do |col|
              { name: col.name, type: col.sql_type, null: col.null, default: col.default }
            end
          end
        end

        def indexes(table)
          with_conn do |c|
            c.indexes(table.to_s).map { |i| { name: i.name, columns: Array(i.columns), unique: i.unique } }
          end
        end

        def count(table)
          with_conn { |c| c.select_value("SELECT count(*) FROM #{c.quote_table_name(table)}").to_i }
        end

        # Lê em lotes de verdade (keyset pagination pela PK), sem carregar a tabela
        # inteira em memória — a diferença entre rodar e não terminar quando
        # `receivable_entries` tiver milhões de linhas.
        def each_batch(table, pk: 'id', batch_size: 1_000, after_pk: nil)
          cursor = after_pk
          loop do
            rows = with_conn do |c|
              quoted = c.quote_table_name(table)
              where = cursor ? "WHERE #{c.quote_column_name(pk)} > #{c.quote(cursor)}" : ''
              c.select_all(
                "SELECT * FROM #{quoted} #{where} ORDER BY #{c.quote_column_name(pk)} ASC LIMIT #{batch_size.to_i}"
              ).to_a
            end
            break if rows.empty?

            yield rows
            cursor = rows.last[pk]
            break if rows.size < batch_size
          end
        end

        def ordered_rows(table, pk: 'id')
          out = []
          each_batch(table, pk: pk) { |batch| out.concat(batch) }
          out
        end

        # Leitura em fluxo, uma linha viva por vez. `ordered_rows` continua existindo
        # para quem precisa do Array, mas ninguém no motor precisa dele para varrer:
        # `risk_entries` tem 642.447 linhas em produção.
        def each_row(table, &block)
          return enum_for(:each_row, table) unless block_given?

          each_batch(table) { |batch| batch.each(&block) }
        end

        # UMA consulta, só a coluna da PK. É contra este conjunto que se conta órfão,
        # e montá-lo a partir de linhas completas era carregar a tabela inteira para
        # extrair um inteiro por linha.
        def pks(table, pk: 'id')
          with_conn do |c|
            c.select_values("SELECT #{c.quote_column_name(pk)} FROM #{c.quote_table_name(table)}")
          end.map(&:to_i).to_set
        end

        private

        def build_pool
          klass = Class.new(ActiveRecord::Base) do
            self.abstract_class = true
          end
          Sfg::Etl::Source.const_set(POOL_NAME, klass) unless Sfg::Etl::Source.const_defined?(POOL_NAME)
          pool_klass = Sfg::Etl::Source.const_get(POOL_NAME)
          pool_klass.establish_connection(@url)
          pool_klass
        end

        def with_conn(&) = @pool.connection_pool.with_connection(&)
      end
    end
  end
end
