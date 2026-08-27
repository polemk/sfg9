# frozen_string_literal: true

module Sfg
  module Etl
    module Source
      # Contrato da ORIGEM. A origem é **somente leitura** e não sabe nada do ai9.
      #
      # Três implementações, e a troca é por parâmetro (`SOURCE=`), nunca por
      # `if` espalhado no motor:
      #
      # * `SqlDump`    — arquivo `pg_dump` em texto. É o que roda HOJE, contra o
      #                  único dump que existe no repositório.
      # * `Connection` — banco vivo do legado (`SFG_LEGACY_URL`). É o do cutover.
      #                  **Depende do usuário** entregar acesso/dump de produção.
      # * `Fixture`    — dado versionado com forma do legado, em `db/etl/fixtures/`.
      #                  Existe para o motor ser exercitável sem dump nenhum.
      #
      # Nenhuma coluna usada pelo ETL é suposta: toda vem daqui (DB-073).
      class Base
        UnavailableSource = Class.new(StandardError)

        def name = self.class.name.demodulize.underscore
        def describe = name

        # Metadados
        def tables = raise(NotImplementedError)
        def columns(_table) = raise(NotImplementedError)
        def indexes(_table) = []
        def table?(table) = tables.include?(table.to_s)
        def column_names(table) = columns(table).map { |c| c[:name] }

        # Volumetria
        def count(_table) = raise(NotImplementedError)

        # Leitura em lotes, **ordenada pela PK** — ordem estável entre execuções
        # é o que faz a retomada chegar ao mesmo estado final (tarefa 6.1).
        def each_batch(table, pk: 'id', batch_size: 1_000, after_pk: nil, &block)
          rows = ordered_rows(table, pk: pk)
          rows = rows.select { |r| r[pk].to_i > after_pk.to_i } if after_pk
          rows.each_slice(batch_size, &block)
        end

        def ordered_rows(_table, pk: 'id') = raise(NotImplementedError)

        # Leitura em fluxo, na ordem em que a origem entrega. Só quem precisa de
        # ordem estável (a carga) paga pela ordenação.
        def each_row(table, &block)
          return enum_for(:each_row, table) unless block_given?

          ordered_rows(table).each(&block)
        end

        # Conjunto de PKs de uma tabela. É contra ele que se conta órfão. A origem
        # pode responder sem montar linha nenhuma — e o `SqlDump` responde, porque
        # `risk_entries` tem 642.447 linhas na produção e montá-las para extrair um
        # inteiro seria trocar segundos por minutos e por um gigabyte.
        def pks(table, pk: 'id')
          ordered_rows(table, pk: pk).each_with_object(Set.new) { |row, set| set << row[pk].to_i }
        end

        def available? = true
      end
    end
  end
end
