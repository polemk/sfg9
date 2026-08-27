# frozen_string_literal: true

module Sfg
  module Etl
    # O **esperado** da origem — DB-ETL-01 parte 2.
    #
    # O legado não versiona `db/schema.rb` (está no `.gitignore:15` dele). A única
    # descrição do esquema que existe são as **139 migrations** (104 do app + 35 das
    # engines). Esta classe as **reexecuta contra um gravador** — não contra um banco —
    # e produz o esquema que elas deveriam ter construído.
    #
    # Reexecutar é melhor que ler com expressão regular por um motivo prático: o DSL
    # do Rails tem `t.references` (duas colunas), `t.attachment` do Paperclip (quatro),
    # `t.timestamps` (duas) e `rename_column`. Regex acerta o caso fácil e erra
    # exatamente onde o ETL dói.
    #
    # O resultado é gravado em `db/etl/legacy_schema.yml`, **versionado**, para que a
    # introspecção rode sem precisar do repositório do legado ao lado.
    module LegacySchema
      BASELINE_PATH = 'db/etl/legacy_schema.yml'

      # Colunas que, SE aparecerem na origem sem estar em migration, **não abortam**
      # (tarefa 3.3). Uma TERCEIRA surpresa aborta.
      #
      # ⚠ **As duas foram medidas contra o dump de produção de 31/05/2025 e NENHUMA
      # DAS DUAS EXISTE.** A tese de que o Safegold tinha "esquema editado fora do
      # versionamento" **não se confirmou**:
      #
      # * `availability_templates.default_position` — zero ocorrência no dump inteiro.
      #   Continua sendo defeito (D-06/D-125): `availability_templates_controller.rb:22`
      #   faz `order!(default_position: :asc)` contra coluna inexistente.
      # * `contracts.description` — `contracts` tem 7 colunas e nenhuma é essa. O
      #   `description` do contrato é `has_rich_text` (`contract.rb:11`): ActionText,
      #   guardado em `action_text_rich_texts` (2 linhas de `Contract` no dump).
      #   **D-108 muda de veredito** — não é schema fora do versionamento.
      #
      # A lista fica porque ela descreve o que é TOLERADO, não o que existe. Removê-la
      # transformaria um reaparecimento em aborto de cutover sem contexto.
      KNOWN_EXTRA_COLUMNS = {
        'availability_templates' => %w[default_position],
        'contracts' => %w[description]
      }.freeze

      # Tabelas que o Rails/gems criam e que nenhuma migration do app declara.
      INFRASTRUCTURE_TABLES = %w[
        schema_migrations ar_internal_metadata
        active_storage_blobs active_storage_attachments active_storage_variant_records
        action_text_rich_texts
      ].freeze

      # Tabelas que a origem pode conter e que NAO sao do esquema Rails do legado:
      # sao lidas como REFERENCIA e nunca migradas. `authentication_user` e a tabela
      # do sistema Django anterior — e por ela que se descobre o Q-16 (a precedencia
      # invertida de papel), e ela so aparece quando a origem e o dump pre-2021.
      REFERENCE_ONLY_TABLES = %w[authentication_user].freeze

      module_function

      def baseline_file = Rails.root.join(BASELINE_PATH)

      # Lê o baseline versionado. Não gera nada: gerar exige o repositório do legado.
      def load_baseline
        raise "baseline ausente: #{baseline_file}. Rode `rake sfg_etl:baseline`." unless baseline_file.exist?

        YAML.safe_load_file(baseline_file, permitted_classes: [Symbol])
      end

      # Regenera o baseline a partir das migrations do legado.
      def build!(legacy_root:)
        root = Pathname.new(legacy_root.to_s)
        raise "repositório do legado não encontrado: #{root}" unless root.directory?

        recorder = Recorder.new
        files = migration_files(root)
        replayed = 0
        failures = []

        files.each do |file|
          replay(file, recorder)
          replayed += 1
        rescue StandardError => e
          failures << { 'file' => file.basename.to_s, 'error' => "#{e.class}: #{e.message}" }
        end

        {
          'generated_at' => Time.current.iso8601,
          'legacy_root' => root.to_s,
          'migrations_total' => files.size,
          'migrations_replayed' => replayed,
          'migrations_failed' => failures,
          'tables' => recorder.to_h
        }
      end

      def write_baseline!(payload)
        baseline_file.dirname.mkpath
        baseline_file.write(<<~HEADER + payload.to_yaml)
          # GERADO por `rake sfg_etl:baseline` — NÃO editar à mão.
          #
          # Esquema ESPERADO da origem, derivado das 139 migrations do legado `sfg`
          # (que não versiona `db/schema.rb`). É o baseline contra o qual
          # `rake sfg_etl:introspect` compara o banco real e ABORTA ao achar surpresa.
        HEADER
        baseline_file
      end

      def migration_files(root)
        (Dir[root.join('db/migrate/*.rb')] + Dir[root.join('engines/*/db/migrate/*.rb')])
          .map { |f| Pathname.new(f) }
          .sort_by { |f| f.basename.to_s }
      end

      # Define a classe da migration num módulo anônimo (para não colidir com as
      # migrations do ai9, que têm nomes iguais — `CreateCarriers` existe nos dois) e
      # chama `change`/`up` com o gravador no lugar do banco.
      def replay(file, recorder)
        mod = Module.new
        mod.module_eval(file.read, file.to_s)
        klass = mod.constants.map { |c| mod.const_get(c) }.find { |c| c.is_a?(Class) }
        return if klass.nil?

        migration = klass.allocate
        migration.singleton_class.prepend(Proxy)
        migration.instance_variable_set(:@etl_recorder, recorder)

        # **`respond_to?` NÃO serve para escolher o método aqui.** `ActiveRecord::
        # Migration` define `up`/`down` de instância que só delegam para o método de
        # classe, então `migration.respond_to?(:up)` é `true` em toda migration, tenha
        # ela `up` ou não. Três migrations do legado usam a forma antiga `def self.up`
        # (Rails 4.2) e uma delas cria as 4 colunas Paperclip de avatar.
        # A pergunta certa é qual método a CLASSE define.
        own = klass.instance_methods(false) + klass.private_instance_methods(false)
        klass_own = klass.singleton_methods(false)

        if own.include?(:change)
          migration.change
        elsif own.include?(:up)
          migration.up
        elsif klass_own.include?(:change)
          klass.delegate = migration
          klass.change
        elsif klass_own.include?(:up)
          migration.up # `Migration#up` delega para `self.class.up`
        end
      end

      # DSL de migration que o gravador não conhece. **Levanta de propósito.**
      #
      # Achado ao rodar contra o dump de produção (26/08/2026): `Proxy` não
      # implementava `change_table`, e `ActiveRecord::Migration#method_missing`
      # embrulha a chamada em `say_with_time { … }` — que o `Proxy` estubava para
      # `nil`. Resultado: **toda chamada de DSL fora desta lista sumia sem erro e
      # sem entrar em `migrations_failed`**, e o baseline saía incompleto calado.
      #
      # Custou 7 falsas "surpresas" na introspecção contra o dump real
      # (`livetat_auth_users.avatar_*`, 4 colunas, e `delayed_jobs.progress_*`, 3) —
      # colunas que as migrations criam e que o baseline não tinha. Um baseline
      # incompleto é pior que baseline ausente: ele aborta o cutover apontando o
      # lugar errado. Agora o desconhecido levanta, e `build!` o registra.
      UnknownDsl = Class.new(StandardError)

      # Intercepta o DSL antes de ele chegar ao adaptador de banco.
      module Proxy
        def create_table(name, **options, &block)
          @etl_recorder.create_table(name, **options, &block)
        end

        # `change_table :tabela do |t| … end` — mesmo bloco de `create_table`, sobre
        # tabela que já existe. As duas migrations do legado que o usam são as que
        # criam as 4 colunas Paperclip de avatar e as 3 de progresso de job.
        def change_table(name, **_options, &block)
          @etl_recorder.change_table(name, &block)
        end

        def add_column(table, column, type, **options) = @etl_recorder.add_column(table, column, type, **options)
        def remove_column(table, column, *_args, **_o) = @etl_recorder.remove_column(table, column)
        def rename_column(table, from, to) = @etl_recorder.rename_column(table, from, to)
        def change_column(table, column, type, **options) = @etl_recorder.add_column(table, column, type, **options)
        def change_column_default(*_args, **_o) = nil
        def change_column_null(*_args, **_o) = nil
        def add_index(table, columns, **options) = @etl_recorder.add_index(table, columns, **options)
        def remove_index(*_args, **_o) = nil
        def drop_table(name, **_o) = @etl_recorder.drop_table(name)
        def rename_table(from, to) = @etl_recorder.rename_table(from, to)
        def add_reference(table, ref, **options) = @etl_recorder.add_reference(table, ref, **options)
        def add_foreign_key(*_args, **_o) = nil
        def remove_foreign_key(*_args, **_o) = nil
        def add_timestamps(table, **_o) = @etl_recorder.add_timestamps(table)
        def remove_timestamps(table, **_o) = %w[created_at updated_at].each { |c|
          @etl_recorder.remove_column(table, c)
        }
        # DSL do Paperclip fora de bloco (`add_attachment :tabela, :avatar`).
        def add_attachment(table, *names) = names.flatten.each { |n| @etl_recorder.add_attachment(table, n) }
        def remove_attachment(table, *names) = names.flatten.each { |n| @etl_recorder.remove_attachment(table, n) }
        # DSL que NÃO muda coluna nem tabela: registrar seria ruído, ignorar é
        # correto. Fica em lista explícita, e não num `method_missing` complacente,
        # para que DSL nova apareça como erro em vez de sumir.
        def execute(*_args) = nil
        def reversible = nil
        def up_only = nil
        def safety_assured = nil
        def say(*_args) = nil
        def say_with_time(*_args) = nil
        def enable_extension(*_args) = nil
        def disable_extension(*_args) = nil
        def create_join_table(*_args, **_o) = nil
        def add_check_constraint(*_args, **_o) = nil
        def remove_check_constraint(*_args, **_o) = nil
        def add_unique_constraint(*_args, **_o) = nil
        def change_column_comment(*_args, **_o) = nil
        def change_table_comment(*_args, **_o) = nil
        def rename_index(*_args, **_o) = nil
        def select_rows(*_args) = []
        def select_all(*_args) = []
        def select_values(*_args) = []
        def select_value(*_args) = nil
        def foreign_key_exists?(*_args, **_o) = false
        def extension_enabled?(*_args) = true
        def quote(value) = "'#{value}'"
        def quote_table_name(value) = %("#{value}")
        def quote_column_name(value) = %("#{value}")

        # Predicados: a verdade é o gravador, nunca um banco. Consultar banco aqui
        # faria o baseline depender do estado do ai9 no dia em que rodou.
        def table_exists?(name) = @etl_recorder.table?(name)
        def column_exists?(table, column, *_a, **_o) = @etl_recorder.column?(table, column)
        def index_exists?(*_args, **_o) = false
        def data_source_exists?(name) = @etl_recorder.table?(name)

        # Nada aqui pode alcançar um banco de verdade. `Migration#method_missing`
        # encaminharia para `ActiveRecord::Base.connection` e executaria DDL no ai9.
        def connection = raise(UnknownDsl, 'o replay do baseline não pode tocar em banco nenhum')

        def method_missing(name, *_args, **_opts)
          raise UnknownDsl, "DSL de migration não suportada pelo gravador: `#{name}`"
        end
      end

      # Gravador: acumula o esquema resultante da sequência de migrations.
      class Recorder
        def initialize = @tables = {}

        def to_h
          @tables.transform_values do |t|
            { 'columns' => t[:columns].map { |name, type| { 'name' => name, 'type' => type } },
              'indexes' => t[:indexes] }
          end
        end

        def table?(name) = @tables.key?(name.to_s)
        def column?(table, column) = @tables.dig(table.to_s, :columns)&.key?(column.to_s) || false

        def create_table(name, **options)
          table = (@tables[name.to_s] ||= { columns: {}, indexes: [] })
          pk = options.fetch(:id, :integer)
          table[:columns]['id'] = pk.to_s unless pk == false
          if block_given?
            builder = TableBuilder.new(table[:columns])
            yield builder
          end
          table
        end

        # `change_table` sobre tabela que já existe: mesmo bloco, sem chave primária.
        def change_table(name)
          table = (@tables[name.to_s] ||= { columns: {}, indexes: [] })
          yield TableBuilder.new(table[:columns]) if block_given?
          table
        end

        def add_timestamps(table)
          add_column(table, 'created_at', :datetime)
          add_column(table, 'updated_at', :datetime)
        end

        def add_attachment(table, name)
          t = (@tables[table.to_s] ||= { columns: {}, indexes: [] })
          TableBuilder.new(t[:columns]).attachment(name)
        end

        def remove_attachment(table, name)
          TableBuilder::PAPERCLIP_SUFFIXES.each { |suffix| remove_column(table, "#{name}_#{suffix}") }
        end

        def rename_table(from, to)
          moved = @tables.delete(from.to_s)
          @tables[to.to_s] = moved if moved
        end

        def add_column(table, column, type, **_o)
          t = (@tables[table.to_s] ||= { columns: {}, indexes: [] })
          t[:columns][column.to_s] = type.to_s
        end

        def remove_column(table, column)
          @tables[table.to_s]&.dig(:columns)&.delete(column.to_s)
        end

        def rename_column(table, from, to)
          t = @tables[table.to_s]
          return if t.nil?

          type = t[:columns].delete(from.to_s)
          t[:columns][to.to_s] = type || 'unknown'
        end

        def add_index(table, columns, **options)
          t = (@tables[table.to_s] ||= { columns: {}, indexes: [] })
          t[:indexes] << { 'columns' => Array(columns).map(&:to_s), 'unique' => !options[:unique].nil? }
        end

        def add_reference(table, ref, **options)
          add_column(table, "#{ref}_id", :integer)
          add_column(table, "#{ref}_type", :string) if options[:polymorphic]
        end

        def drop_table(name) = @tables.delete(name.to_s)
      end

      # `t.<qualquer tipo> :coluna`. `method_missing` cobre o DSL inteiro, inclusive
      # `t.attachment` do Paperclip (que vira QUATRO colunas — é isso que uma regex
      # perderia) e `t.references` polimórfico (que vira duas).
      class TableBuilder
        PAPERCLIP_SUFFIXES = %w[file_name content_type file_size updated_at].freeze

        def initialize(columns) = @columns = columns

        def timestamps(**_o)
          @columns['created_at'] = 'datetime'
          @columns['updated_at'] = 'datetime'
        end

        def attachment(name, **_o)
          PAPERCLIP_SUFFIXES.each do |suffix|
            @columns["#{name}_#{suffix}"] = suffix == 'file_size' ? 'integer' : 'string'
          end
          @columns["#{name}_updated_at"] = 'datetime'
        end

        def references(name, **options)
          @columns["#{name}_id"] = 'integer'
          @columns["#{name}_type"] = 'string' if options[:polymorphic]
        end
        alias belongs_to references

        def index(*_args, **_o) = nil

        # `t.foreign_key :active_storage_blobs, column: :blob_id` NÃO é coluna. Sem
        # esta linha o `method_missing` abaixo gravava uma coluna fantasma chamada
        # `active_storage_blobs` na tabela `active_storage_attachments`, que a
        # introspecção depois relatava como "declarada por migration e ausente na
        # origem" — ruído que não existe.
        def foreign_key(*_args, **_o) = nil
        def check_constraint(*_args, **_o) = nil

        def method_missing(type, *names, **_options)
          names.flatten.each { |n| @columns[n.to_s] = type.to_s }
        end

        def respond_to_missing?(*) = true
      end
    end
  end
end
