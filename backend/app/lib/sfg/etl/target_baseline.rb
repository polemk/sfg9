# frozen_string_literal: true

module Sfg
  module Etl
    # O PORTÃO DE SCHEMA DO DESTINO — OPS-549 (parte 2), tarefas 1.2 e 3.4.
    #
    # Responde uma pergunta só: **o `schema.rb` declara alguma tabela que nenhuma
    # migration cria?**
    #
    # Por que isso importa aqui e não em outra fatia: um `db:schema:load` num ambiente
    # novo criaria essas tabelas do nada, e ninguém saberia de onde vieram. E elas
    # **contaminam o baseline de introspecção do ETL** — sem a allowlist, a
    # introspecção aborta contra o próprio destino (C-07/F-08).
    #
    # A allowlist é EXPLÍCITA e nominal. Não é um filtro por prefixo: acrescentar uma
    # tabela órfã nova tem de **falhar**, e as antigas ficam visíveis em vez de
    # invisíveis. É a diferença entre dívida registrada e dívida escondida.
    module TargetBaseline
      # As ~25 órfãs herdadas da base ai9: existem no `schema.rb`, sem model, sem
      # migration e sem referência. Derrubá-las exige saber se algum outro sistema da
      # base ainda as usa — por isso ficam declaradas, não removidas.
      INHERITED_ORPHANS = %w[
        achievements user_achievements drops point_events
        budgets budget_items budget_members
        fly_active_timers fly_direct_messages fly_drops fly_houses fly_inventory_slots
        fly_livros fly_meeting_invites fly_meetings fly_npcs fly_outdoor_campaigns
        fly_outdoor_events fly_outdoors fly_profiles fly_transacoes fly_zones
        work_cycles work_item_assignees work_item_labels work_items work_labels
        work_projects work_states work_time_sessions
      ].freeze

      # Criadas pelo Rails/gems, não por migration do app.
      FRAMEWORK_TABLES = %w[
        schema_migrations ar_internal_metadata
        active_storage_blobs active_storage_attachments active_storage_variant_records
        action_text_rich_texts versions
      ].freeze

      module_function

      def schema_tables(path = Rails.root.join('db/schema.rb'))
        Pathname.new(path).read.scan(/create_table "([^"]+)"/).flatten.sort
      end

      # Tabelas que as migrations do ai9 criam. Usa o mesmo replay das migrations do
      # legado — o DSL é o mesmo, e ler com regex perderia `create_table` com opções
      # em várias linhas.
      # Migration que o gravador não conseguiu reexecutar. **Não é detalhe**: uma
      # migration pulada some com as tabelas que ela cria, e o portão passa a acusar
      # tabela "sem migration" que tem migration. Era exatamente isto que o
      # `rescue StandardError; next` escondia — e é o mesmo modo de falha que deixou
      # o baseline do LEGADO incompleto por dois dias.
      def replay_failures(dir = Rails.root.join('db/migrate'))
        collect(dir).last
      end

      def migration_tables(dir = Rails.root.join('db/migrate'))
        collect(dir).first
      end

      # Sem memoização de propósito: o diretório de migrations muda no meio do dia,
      # com outras fatias entregando, e um portão que responde com resultado velho é
      # pior que um portão lento.
      def collect(dir)
        recorder = LegacySchema::Recorder.new
        failures = []
        Dir[Pathname.new(dir).join('*.rb')].sort.each do |file|
          LegacySchema.replay(Pathname.new(file), recorder)
        rescue StandardError => e
          failures << "#{File.basename(file)}: #{e.class}: #{e.message.lines.first.to_s.strip}"
        end
        [recorder.to_h.keys.sort, failures]
      end

      # Tabelas declaradas no `schema.rb` e criadas por nenhuma migration, fora a
      # allowlist. Vazio = portão verde.
      def undeclared_tables
        schema_tables - migration_tables - INHERITED_ORPHANS - FRAMEWORK_TABLES
      end

      # As órfãs que continuam lá. Não falham o portão; ficam VISÍVEIS.
      def known_orphans_present
        schema_tables & INHERITED_ORPHANS
      end

      # Allowlist do ETL: nada disto entra em contagem, dry-run ou reconciliação.
      def ignored_by_etl = (INHERITED_ORPHANS + FRAMEWORK_TABLES).sort
    end
  end
end
