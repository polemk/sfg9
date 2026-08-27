# frozen_string_literal: true

module Demo
  module Writers
    # Contrato comum dos escritores do seed de demonstração.
    #
    # O escritor é a **única** camada que conhece o banco. O razão não sabe que
    # existe tabela; é por isso que ele roda hoje, antes de S3..S11 (DEC-64).
    #
    # Três responsabilidades, e nada além:
    #
    # 1. **Declarar o que exige.** `requires` lista os models. Faltando um, o
    #    módulo pula — com aviso nomeando o model e a fatia dona.
    # 2. **Traduzir campo do razão em coluna.** É aqui, e só aqui, que
    #    `movement.sequence` encontra a coluna `sequence` (o `order` do legado,
    #    renomeado por DB-236).
    # 3. **Gravar por chave natural.** Nunca `create`: sempre
    #    `find_or_initialize_by` com a chave que a fatia dona já indexou.
    class Base
      Result = Struct.new(:writer, :status, :created, :updated, :unchanged, :message,
                          :skipped_attributes, keyword_init: true) do
        def total = created.to_i + updated.to_i + unchanged.to_i
      end

      class << self
        # Models exigidos. Vazio = roda sempre.
        def requires = []

        # Fatia que entrega os models — entra na mensagem de pulo, para que quem
        # ler o relatório saiba de quem depende.
        def owner_slice = nil

        def writer_name = name.split('::').last.gsub(/(?<!\A)([A-Z])/, '_\1').downcase

        def missing_models
          requires.reject { |model| Object.const_defined?(model) && table_ready?(model) }
        end

        # Model definido não basta: numa base recém-clonada a classe pode existir
        # sem a tabela ter sido migrada. Perguntar ao banco evita um erro no meio
        # do seed, na véspera da demo.
        # Título comparável: sem acento, sem caixa e sem espaço de sobra. É o que
        # permite adotar uma linha criada à mão (`Recebiveis a vencer`) em vez de
        # duplicá-la com a versão acentuada.
        def normalized_title(value)
          I18n.transliterate(value.to_s).downcase.strip.squeeze(' ')
        end

        def table_ready?(model)
          klass = Object.const_get(model)
          klass.respond_to?(:table_exists?) && klass.table_exists?
        rescue StandardError
          false
        end
      end

      def initialize(ledger, io: $stdout)
        @ledger = ledger
        @io = io
        @created = 0
        @updated = 0
        @unchanged = 0
        @skipped_attributes = Set.new
      end

      attr_reader :ledger, :io

      def run
        missing = self.class.missing_models
        if missing.any?
          return Result.new(
            writer: self.class.writer_name, status: :skipped,
            created: 0, updated: 0, unchanged: 0, skipped_attributes: [],
            message: "#{missing.join(', ')} ainda não #{missing.one? ? 'existe' : 'existem'}" \
                     "#{self.class.owner_slice ? " (chega na #{self.class.owner_slice})" : ''}"
          )
        end

        ActiveRecord::Base.transaction { call }

        Result.new(writer: self.class.writer_name, status: :ok,
                   created: @created, updated: @updated, unchanged: @unchanged,
                   skipped_attributes: @skipped_attributes.to_a.sort)
      rescue StandardError => e
        # **Por que o erro não sobe.** Cinco fatias entregam model nesta semana, e
        # cada entrega pode acrescentar uma validação que este escritor ainda não
        # conhece. Deixar a exceção subir faz UM escritor novo derrubar os
        # dezesseis que já funcionavam — e o que sobra na véspera da demonstração
        # é um banco vazio, não um banco com um agregado a menos.
        #
        # O erro **não é engolido**: a transação deste escritor voltou atrás
        # sozinha, o relatório imprime `✖ FALHOU`, o resultado carrega a mensagem
        # e `rake demo:seed` termina com status diferente de zero. Falha barulhenta
        # e parcial, em vez de silenciosa e total.
        Result.new(writer: self.class.writer_name, status: :failed,
                   created: 0, updated: 0, unchanged: 0,
                   skipped_attributes: @skipped_attributes.to_a.sort,
                   message: "#{e.class}: #{e.message}")
      end

      # Cada escritor implementa isto.
      def call
        raise NotImplementedError
      end

      protected

      # Grava um registro pela **chave natural**. Devolve o registro.
      #
      # O `attributes` pode trazer campos que a fatia dona ainda não criou (é o
      # caso de `projects.formal` e `closing_date`, que só nascem na S4): eles são
      # **ignorados com registro**, e aparecem no relatório. Assim o seed grava o
      # que dá hoje e passa a gravar o resto sozinho quando a coluna existir.
      def upsert!(model, find_by:, attributes: {})
        persist!(model.find_or_initialize_by(**find_by), attributes)
      end

      # A metade do `upsert!` que **já tem o registro em mãos**. Existe porque
      # nem toda chave natural é um `find_or_initialize_by`: a árvore de padrões
      # de disponibilidade casa por título **normalizado** dentro do pai (é o que
      # permite adotar a linha que alguém criou à mão sem acento, em vez de
      # duplicá-la e bater no índice único).
      def persist!(record, attributes)
        fresh = record.new_record?
        assign(record, attributes)

        if fresh
          record.save!
          @created += 1
        elsif record.changed?
          record.save!
          @updated += 1
        else
          @unchanged += 1
        end
        record
      end

      def assign(record, attributes)
        columns = record.class.column_names
        attributes.each do |key, value|
          name = key.to_s
          if columns.include?(name) || record.respond_to?(:"#{name}=")
            record.public_send(:"#{name}=", value)
          else
            @skipped_attributes << "#{record.class.name}##{name}"
          end
        end
      end

      # Só grava se a coluna existir — para campos cujo nome ainda está em aberto
      # no desenho da fatia dona (ex.: `projects.slug` vs `smart_id`).
      def first_available_column(model, *candidates)
        candidates.map(&:to_s).find { |c| model.column_names.include?(c) }
      end

      # ------------------------------------------------------------------
      # Resolvedores — do registro do razão para a linha já gravada
      # ------------------------------------------------------------------
      # Cada escritor grava um agregado e **resolve** os anteriores por chave
      # natural. É o que mantém a ordem de execução sendo dependência real, e não
      # convenção.
      def projects_by_slug
        @projects_by_slug ||= ::Project.where(slug: ledger.clients.map(&:slug)).index_by(&:slug)
      end

      def carriers_by_code
        @carriers_by_code ||= ::Carrier.where(bank_code: ledger.carriers.map(&:bank_code))
                                       .index_by(&:bank_code)
      end

      # `companies` tem índice único `(project_id, title)` — é essa a chave.
      def companies_by_key
        @companies_by_key ||= ledger.companies.each_with_object({}) do |company, acc|
          project = projects_by_slug[company.client.slug]
          next if project.nil?

          record = ::Company.find_by(project_id: project.id, title: company.title)
          acc[company.key] = record if record
        end
      end

      def project_for(client)
        projects_by_slug[client.slug]
      end

      # O autor das linhas que exigem um. **É o Admin do elenco, nunca o OG**: o
      # OG é o fornecedor, e carimbá-lo como autor de lançamento de cliente
      # inventa uma trilha que nenhuma operação real produziria. Cai para
      # qualquer administrador existente se o elenco ainda não foi gravado.
      def demo_author
        return @demo_author if defined?(@demo_author)

        email = ledger.cast.find { |m| m[:key] == :admin }&.dig(:email)
        @demo_author = ::User.find_by(email: email) ||
                       ::User.joins(:user_type).where(user_types: { name: 'admin' }).first
      end

      def carrier_for(carrier)
        carriers_by_code[carrier.bank_code]
      end
    end
  end
end
