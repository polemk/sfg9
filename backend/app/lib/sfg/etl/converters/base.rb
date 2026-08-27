# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # ==========================================================================
      # ESTE É O PONTO DE ENTRADA DE TODO CONVERSOR DE DOMÍNIO.
      # ==========================================================================
      #
      # O desenho é o mesmo que a **S20** usou em `db/seeds/demo/` e que funcionou:
      # o **razão** (aqui, `Source`, que só lê o legado) separado dos **escritores**
      # (aqui, os conversores), e cada escritor **declarando o que precisa** e
      # **pulando com aviso, nomeando o model e a fatia**, quando o model ainda não
      # existe. É o que faz o ETL rodar HOJE, com S5..S11 ainda no meio do caminho.
      #
      # Um ETL que só roda quando tudo existir é um ETL que ninguém testou — e o
      # primeiro teste dele seria a janela de cutover.
      #
      # --------------------------------------------------------------------------
      # COMO PLUGAR UM CONVERSOR NOVO (é isto, e só isto)
      # --------------------------------------------------------------------------
      #
      #   1. crie `app/lib/sfg/etl/converters/<nome>.rb`
      #   2. herde de `Base` e declare:
      #
      #        class RiskOperations < Base
      #          def self.source_table = 'risk_operations'   # tabela NO LEGADO
      #          def self.target_model = 'RiskOperation'     # model NO ai9 (string!)
      #          def self.requires     = %w[RiskOperation RiskControl Company]
      #          def self.owner_slice  = 'S7'                # quem entrega o model
      #          def self.references   = { 'project_id' => 'projects',
      #                                    'risk_control_id' => 'risk_controls' }
      #          def self.booleans     = %w[is_active]       # int 0/1 do legado
      #          def self.enums        = { 'status' => Values::RECEIVABLE_STATUS }
      #          def self.uniques      = [%w[project_id contract_number]]
      #
      #          def natural_key(row) = { legacy_id: row['id'] }
      #
      #          def convert(row)
      #            { contract_number: row['contract_number'],
      #              project_id: ref('projects', row['project_id']),
      #              operation_value: Values.to_decimal(row['operation_value']) }
      #          end
      #        end
      #
      #   3. acrescente a classe em `db/etl/load_order.yml`, na posição de dependência.
      #
      # Nada mais. Ordem, lote, transação, checkpoint, retomada, idempotência,
      # religamento de FK, contagem de órfão, contagem de duplicata, conversão de
      # booleano/enum/timestamp e reconciliação **são do motor**, e o conversor não
      # os reimplementa.
      #
      # **Referências de model são STRING, sempre.** `RiskOperation` como constante
      # explodiria o carregamento inteiro do ETL enquanto a S7 não entregar o model —
      # e é justamente por isso que o de-para é resolvido em tempo de execução.
      class Base
        # `rejected` — linhas que o destino RECUSOU por validação (DEC-127). Não
        # entraram, saíram listadas, e a carga seguiu.
        Outcome = Struct.new(:converter, :status, :read, :written, :skipped, :orphans,
                             :anomalies, :message, :unknown_attributes, :rejected, keyword_init: true) do
          def rejected = self[:rejected].to_i
        end

        class << self
          # ------------------------------------------------------- declarações
          def source_table = raise(NotImplementedError, "#{name} precisa declarar `source_table`")
          def target_model = raise(NotImplementedError, "#{name} precisa declarar `target_model`")

          # Models do ai9 sem os quais este conversor não roda. Faltando um, o
          # conversor **pula com aviso** — não quebra a execução.
          def requires = [target_model]

          # Fatia dona dos models exigidos. Entra na mensagem de pulo, para que quem
          # lê o relatório saiba **de quem** este passo depende.
          def owner_slice = nil

          def legacy_pk = 'id'

          # Tabelas da origem que este conversor **lê junto** e que por isso não têm
          # entrada própria na ordem de carga (o caso arquetípico é `Users`, que lê
          # `livetat_auth_roles`, `livetat_auth_role_types` e `livetat_auth_user_infos`
          # para montar UM usuário). Sem esta declaração a conferência de cobertura da
          # introspecção as acusa como "dado de produção que ninguém reivindicou" —
          # e um aviso que sempre aparece é um aviso que ninguém lê.
          def also_reads = []

          # `coluna da origem => tabela da origem apontada`. O motor usa isto para
          # religar **exclusivamente pelo de-para** e para contar órfãos (DB-ETL-03).
          def references = {}

          # `coluna do ai9 => [tabela da origem, coluna da origem]`. Referências que só
          # podem resolver DEPOIS de toda a fila rodar, porque fecham um CICLO
          # (`users.default_project_id` -> `projects.segment_id` -> `segments.user_id` ->
          # `users`). O motor faz um **segundo passo** ao fim da carga.
          #
          # O ETL de 2021 resolvia o mesmo ciclo de outro jeito: forçava o autor para um
          # identificador FIXO em portadores e recebíveis (BE-452 (a)) — e esses registros
          # estão em produção com autoria errada por construção. O segundo passo é a
          # correção desse desenho, não uma otimização.
          def deferred = {}

          # Colunas que no legado são `integer` 0/1 (regra D-E). O motor reporta todo
          # valor fora de `{0,1}` **antes** de converter.
          def booleans = []

          # `coluna => de-para` para os enums-string em pt-BR (BE-445/BE-448).
          def enums = {}

          # Unicidades compostas que o legado só validava em aplicação. O motor conta
          # duplicatas na ORIGEM e **bloqueia o índice único** até resolução (5.3).
          def uniques = []

          # Colunas de data/hora a converter para UTC. `nil` = deduzir do esquema da
          # origem (o padrão; é o que satisfaz DB-073 — nada é suposto).
          def timestamps = nil

          # `coluna => nota`. Campos cuja origem JÁ chega truncada (o arquetípico é
          # `street_number`, int na origem e string no destino — D-V: "12A" virou "12"
          # anos atrás e não há como recuperar). Reportar é o único tratamento honesto.
          def truncations = {}

          # Colunas monetárias somadas na reconciliação (7.3), por tabela e por ano.
          # É o que pega erro de cast e de **sinal** — o erro que some numa amostra e
          # aparece no total.
          def sums = []

          def year_column = 'created_at'

          # Colunas cujo valor o **model do ai9 calcula ou normaliza**, e que por isso
          # NÃO se comparam literalmente com a origem na reconciliação.
          #
          # Achado ao executar: `carriers.subordinated_accounts_percent` é derivado no
          # servidor (DC-09, `carrier.rb:164-172`) e `users.phone` é normalizado. Sem
          # esta declaração a reconciliação acusa divergência em toda linha — ruído que
          # esconde a divergência de verdade.
          def derived = []

          def converter_name = name.split('::').last.gsub(/(?<!\A)([A-Z])/, '_\1').downcase

          # ------------------------------------------------------- pós-carga
          #
          # **GANCHO OPCIONAL, chamado pelo motor (`Run#run_post_load!`) logo
          # depois de as linhas deste conversor entrarem, e SÓ no modo `:load`.**
          #
          # Existe para o que não dá para decidir dentro de um lote, porque
          # depende do conjunto inteiro: quem é o subtipo de MENOR `legacy_id` do
          # tipo (DEC-67, `is_default_for_type`), quantas linhas de cada formato
          # ficaram (DEC-43), se as chaves funcionais chegaram.
          #
          # Devolve um Hash — o motor o transcreve para o relatório sem
          # interpretar. Levantar aqui **reprova a carga** (severidade `:reject`)
          # sem interromper os conversores seguintes.
          #
          # Precisa ser **idempotente**: a carga é retomável e re-executável, e
          # este gancho roda em toda execução.
          #
          # Declarar é opt-in: `Base` **não** define `post_load!`, e o motor
          # pergunta com `respond_to?`. Foi justamente a falta desta declaração —
          # o gancho existindo em quatro conversores e o motor não sabendo dele —
          # que deixou o `is_default_for_type` da DEC-67 sem ser marcado numa
          # carga real, provado só por um spec que chamava o método na mão.
          #
          #   def self.post_load!
          #     return { marked: 0 } unless model_ready?('RiskOperationSubtype')
          #     …
          #   end
          def post_load? = respond_to?(:post_load!)

          # ---------------------------------------------------- disponibilidade
          def missing_models
            requires.reject { |model| model_ready?(model) }
          end

          # Classe definida não basta: numa base recém-clonada ela pode existir sem a
          # tabela ter sido migrada. Perguntar ao banco evita estourar no meio da
          # carga — foi a lição que a S20 registrou no `Writers::Base`.
          def model_ready?(model)
            return false unless Object.const_defined?(model)

            klass = Object.const_get(model)
            klass.respond_to?(:table_exists?) && klass.table_exists?
          rescue StandardError
            false
          end

          def target_class = Object.const_get(target_model)

          def skip_message
            missing = missing_models
            "#{missing.join(', ')} ainda não #{missing.one? ? 'existe' : 'existem'} no ai9" \
              "#{owner_slice ? " — chega na #{owner_slice}" : ''}"
          end
        end

        def initialize(run)
          @run = run
          @unknown_attributes = Set.new
        end

        attr_reader :run

        delegate :source, :report, :run_id, :dry_run?, :io, to: :run

        # ------------------------------------------------------------ contrato
        # Cada conversor implementa estes dois.

        # `row` (Hash de colunas da ORIGEM) => Hash de atributos do ai9.
        def convert(_row) = raise(NotImplementedError)

        # Chave natural do destino. É por ela que a gravação é `find_or_initialize_by`
        # em vez de `create` — a segunda rede de idempotência, depois do de-para.
        def natural_key(row) = { legacy_id: row[self.class.legacy_pk] }

        # Anomalias específicas do conversor (ex.: a precedência de papel do Q-16).
        # Roda no dry-run **e** na carga.
        #
        # Devolve um Array de:
        #   * `String` — a linha de relatório (o retorno de `Values.anomaly_line`).
        #     Cai numa chave de decisão única por conversor. É o que 11 dos 13
        #     conversores usam.
        #   * `{ key:, title:, line: }` — quando o conversor quer **chave de decisão
        #     própria** por família de anomalia, para autorizar uma e barrar outra
        #     em `db/etl/decisions.yml`.
        #
        # As duas formas convivem: `Scan#normalized_custom` normaliza.
        def anomalies(_row) = []

        # ------------------------------------------------------------ auxílio

        # Religamento de FK — **exclusivamente pelo de-para**. Nunca reaproveita o id
        # numérico da origem: um `bigint` apontando para tabela `uuid` derrubou o login
        # em 25/08/2026, e num banco todo-inteiro associaria o registro errado calado.
        #
        # Sem correspondência devolve `nil` e a linha é **contada como órfã**.
        def ref(source_table, legacy_pk)
          return nil if legacy_pk.nil? || legacy_pk.to_s.strip.empty?

          run.resolve_reference(source_table, legacy_pk)
        end

        def unknown_attributes = @unknown_attributes.to_a.sort

        # Grava um registro. Só o motor chama.
        def write!(row, attributes)
          klass = self.class.target_class
          record = klass.find_or_initialize_by(**natural_key(row))
          # **DEC-112** — o carimbo de `has_safegold_management` É o dado
          # histórico, e o `save!` abaixo dispara o `before_validation` que o
          # recopia do projeto. Sem esta linha, carregar o dump sobrescreveria o
          # carimbo de cada linha pelo valor **de hoje** e apagaria justamente a
          # inconsistência que a decisão mandou preservar — em silêncio, sem
          # erro, em 28.131 recebíveis e 642.447 posições de risco.
          #
          # Só vale quando a ORIGEM trouxe o valor: converter que não o declara
          # continua deixando o callback carimbar.
          if attributes.key?(:has_safegold_management) && record.respond_to?(:preserve_safegold_stamp=)
            record.preserve_safegold_stamp = true
          end
          # **Carga não é digitação.** O model que declara `etl_loading` tem
          # callbacks que DERIVAM valor a partir de outras linhas — desenhados
          # para o usuário editando a grade, quando o resto tem mesmo de se
          # ajustar. Na carga eles reescrevem o dado copiado e chegam a CRIAR
          # linhas que a origem já tem, com `legacy_id` nulo: a segunda leva
          # bate no índice de unicidade e derruba o lote inteiro.
          #
          # Só os models que pedem a chave são afetados; os outros não têm o
          # acessor e seguem com os callbacks todos ligados.
          record.etl_loading = true if record.respond_to?(:etl_loading=)
          assign(record, attributes)
          # `touch: false` — sem isto o Rails carimba `updated_at = Time.current` numa
          # ATUALIZAÇÃO cujo `updated_at` atribuído coincide com o já gravado (não conta
          # como "changed") mas cujo registro ficou sujo por um callback do model.
          # Achado ao executar: os portadores voltaram da 2ª carga com `updated_at` de
          # hoje, e a data de atualização do legado é dado, não metadado.
          record.save!(touch: false)
          record
        end

        private

        # Atributo cuja coluna a fatia dona ainda não criou é **ignorado com
        # registro**, e aparece no relatório. Assim o ETL grava o que dá hoje e passa
        # a gravar o resto sozinho quando a coluna existir — mesmo desenho do
        # `Demo::Writers::Base#assign`.
        def assign(record, attributes)
          columns = record.class.column_names
          attributes.each do |key, value|
            name = key.to_s
            if columns.include?(name) || record.respond_to?(:"#{name}=")
              record.public_send(:"#{name}=", value)
            else
              @unknown_attributes << "#{record.class.name}##{name}"
            end
          end
        end
      end
    end
  end
end
