# frozen_string_literal: true

module Sfg
  module Etl
    # O MOTOR. Uma execução do ETL, em um de dois modos: `:dry_run` (não escreve
    # nada) e `:load` (escreve).
    #
    # Tudo que é difícil num ETL mora aqui e **não** nos conversores:
    #
    # * **lotes** ordenados pela PK da origem — ordem estável entre execuções;
    # * **transação por lote** com o checkpoint gravado DENTRO dela;
    # * **retomada** a partir do checkpoint;
    # * **idempotência** pelo de-para (`etl_id_map`), consultado antes de inserir;
    # * **religamento de FK exclusivamente pelo de-para**;
    # * **contagem** de órfãos, duplicatas, booleanos fora de {0,1}, enums fora do
    #   de-para e timestamps ambíguos;
    # * **aborto** quando uma contagem maior que zero não tem decisão registrada.
    class Run
      MODES = %i[dry_run load].freeze

      # Levantada quando a carga é impedida por anomalia sem decisão registrada.
      # **Antes de escrever a primeira linha** — é o que separa "abortou" de
      # "abortou no meio".
      Blocked = Class.new(StandardError)

      # Uma linha da origem que o destino RECUSOU por validação — DEC-127.
      #
      # Uma linha pode falhar por mais de um motivo, e há **uma `Rejection` por
      # motivo**: é o que permite agrupar por causa no fim ("90 linhas por
      # `title: não pode ficar em branco`") em vez de por linha.
      #
      # **Privacidade (DEC-123):** só entram `legacy_pk`, tabela, coluna e a
      # MENSAGEM da validação. Nunca o valor. `errors#message` é a mensagem crua
      # ("não pode ficar em branco"), diferente de `full_message`, que prefixa o
      # nome do atributo e, em validador customizado, às vezes interpola o valor.
      Rejection = Struct.new(:source_table, :target_model, :legacy_pk, :attribute, :message,
                             keyword_init: true) do
        # A causa, sem o id — é por ela que o resumo agrupa.
        def cause = "`#{source_table}`.`#{attribute}` — #{message}"
      end

      def initialize(source:, mode: :dry_run, report: nil, run_id: nil, batch_size: 1_000,
                     io: $stdout, only: nil, decisions: nil, resume: true)
        raise ArgumentError, "modo inválido: #{mode}" unless MODES.include?(mode)

        @source = source
        @mode = mode
        @report = report || Report.new(mode.to_s, io: io)
        @run_id = run_id || 'default'
        @batch_size = batch_size.to_i
        @io = io
        @only = Array(only).map(&:to_s).presence
        @decisions = decisions || Decisions.load
        @resume = resume
        @pk_cache = {}
        @id_cache = {}
        @unresolved = Hash.new(0)
        @resolved = Hash.new(0)
        @rejections = []
      end

      attr_reader :source, :mode, :report, :run_id, :batch_size, :io, :decisions, :rejections

      def dry_run? = mode == :dry_run

      # ---------------------------------------------------------------- execução

      def execute!
        report.meta('modo', mode)
        report.meta('origem', source.describe)
        report.meta('execução (run_id)', run_id)
        report.meta('lote', batch_size)

        outcomes = pipeline.map { |converter_class| run_converter(converter_class) }
        resolve_deferred! unless dry_run?
        summary_section(outcomes)
        rejection_summary_section unless dry_run?
        relink_section unless dry_run?
        outcomes
      end

      def pipeline
        list = Pipeline.converters
        return list if @only.nil?

        list.select { |c| @only.include?(c.converter_name) || @only.include?(c.source_table) }
      end

      # ---------------------------------------------------------- um conversor

      def run_converter(converter_class)
        name = converter_class.converter_name
        table = converter_class.source_table

        missing = converter_class.missing_models
        return skipped(converter_class, converter_class.skip_message) if missing.any?
        return skipped(converter_class, "tabela `#{table}` não existe nesta origem") unless source.table?(table)

        converter = converter_class.new(self)
        scan = Scan.new(self, converter).run!

        unless dry_run?
          # A carga NÃO começa com anomalia pendente. O aborto acontece **antes da
          # primeira escrita**, e não no meio — que é a diferença entre um banco
          # limpo e um banco pela metade.
          if report.aborted?
            raise Blocked, "carga bloqueada em `#{name}`: #{report.abort_sections.map(&:title).join('; ')}"
          end

          outcome = load_rows(converter, scan)
          run_post_load!(converter_class)
          return outcome
        end

        Converters::Base::Outcome.new(
          converter: name, status: :dry_run, read: scan.read, written: 0,
          skipped: 0, orphans: scan.orphan_total, anomalies: scan.anomaly_total,
          unknown_attributes: []
        )
      end

      def skipped(converter_class, message)
        report.section("PULADO — #{converter_class.converter_name}", severity: :warn) do |lines|
          lines << "- #{message}"
          lines << "- origem: `#{converter_class.source_table}` · destino: `#{converter_class.target_model}`"
          lines << '- rode de novo quando a fatia dona entregar: o motor é idempotente.'
        end
        io.puts format('  %<icon>s %-26<name>s %<msg>s', icon: '»', name: converter_class.converter_name, msg: message)
        Converters::Base::Outcome.new(converter: converter_class.converter_name, status: :skipped,
                                      read: 0, written: 0, skipped: 0, orphans: 0, anomalies: 0,
                                      message: message, unknown_attributes: [])
      end

      # ------------------------------------------------------------------ carga

      def load_rows(converter, scan)
        klass = converter.class
        checkpoint = Checkpoint.for(run_id: run_id, source_table: klass.source_table)
        after = @resume ? checkpoint.last_legacy_pk : nil
        mapped = IdMap.cache_for(klass.source_table)

        read = 0
        written = 0
        skipped = 0
        rejected = []

        source.each_batch(klass.source_table, pk: klass.legacy_pk, batch_size: batch_size, after_pk: after) do |batch|
          batch_written = 0
          batch_skipped = 0
          last_pk = nil

          # ================================================================
          # `no_touching` ENVOLVE a transação, e não é detalhe de arrumação.
          # ================================================================
          #
          # **Achado ao executar (S14, 26/08/2026), com a reconciliação como
          # testemunha: 25 de 25 itens de ajuda voltaram da carga com
          # `updated_at` de HOJE.** `created_at` chegou certo; só a data de
          # atualização se perdeu — o jeito mais silencioso possível de perder
          # um dado, porque a coluna está preenchida e ninguém desconfia.
          #
          # A causa é `ActionText::RichText`, que declara
          # `belongs_to :record, polymorphic: true, touch: true`. Gravar o corpo
          # **toca o registro dono**. Vale para os três donos de texto rico desta
          # migração — `Indicator` (485 corpos), `HelpItem` (25) e `Contract`
          # (2) — e vale tanto quando o conversor do dono atribui o corpo quanto
          # quando `Converters::ActionTextRichTexts` grava a linha depois.
          #
          # O `save!(touch: false)` do `Converters::Base#write!` **não cobre
          # isto**: aquilo desliga o toque DESTE registro; este vem do FILHO.
          #
          # E corrigir depois do `save!` também não funciona: dentro de uma
          # transação o Rails usa `touch_later`, que ADIA o carimbo para o
          # commit. Qualquer `update_columns` do conversor roda antes e é
          # sobrescrito na saída da transação — medido, foi a primeira tentativa
          # de correção e ela falhou em silêncio.
          #
          # `no_touching` neutraliza `touch` **e** `touch_later`, e por isso
          # precisa envolver a transação inteira, não só o `save!`.
          #
          # A regra que ele grava, e que vale para toda a carga: **`created_at` e
          # `updated_at` vêm da ORIGEM. O ETL não carimba data.** É a mesma razão
          # já registrada em `Base#write!` — "a data de atualização do legado é
          # dado, não metadado".
          #
          # Transação POR LOTE, com o checkpoint dentro dela. Matar o processo aqui
          # deixa o banco consistente no último lote completo — é o teste de 6.2.
          ActiveRecord::Base.no_touching do
            ActiveRecord::Base.transaction do
              batch.each do |row|
                pk = row[klass.legacy_pk]
                last_pk = pk
                read += 1

                # Idempotência: linha já mapeada = pular, sem tocar no destino.
                if mapped.key?(pk.to_i)
                  batch_skipped += 1
                  next
                end

                # ==========================================================
                # DEC-127 — A LINHA INVÁLIDA NÃO ENTRA, SAI LISTADA, E A
                # CARGA SEGUE.
                # ==========================================================
                #
                # **Isto NÃO é "ignorar erro".** A linha continua não sendo
                # carregada, e o relatório termina reprovado
                # (`Report#rejected?` -> o rake sai com status de falha). O
                # que muda é que a execução **não morre na primeira**.
                #
                # O defeito que isto conserta (D-PAR-04) custou o dia
                # 27/08/2026 inteiro: `save!` sem resgate fazia a carga morrer
                # na primeira linha inválida, então se descobria **um defeito
                # por execução** — e a execução completa leva ~1h só de
                # `risk_entries` (642.447 linhas). Slug com `&`, CEP de 7
                # dígitos, título vazio, `NaN` nos derivados, `providers`
                # ausente: cada um só apareceu depois de o anterior sair do
                # caminho, e não havia como saber quantos faltavam.
                #
                # **Por que só `RecordInvalid`, e por que isso é seguro dentro
                # da transação do lote.** `save!` valida ANTES de emitir SQL:
                # quando ele levanta `RecordInvalid` nenhum comando chegou ao
                # Postgres, então a transação do lote continua íntegra e os
                # registros válidos do mesmo lote entram normalmente. Um erro
                # de banco (`StatementInvalid`, `RecordNotUnique`) é outra
                # história: ele **aborta a transação** no servidor, e seguir
                # ali dentro exigiria savepoint por linha — caro em 642.447
                # linhas e, mais importante, seria esconder um defeito de
                # esquema ou de conversor, que precisa ser barulhento. Esses
                # continuam derrubando a execução, de propósito.
                #
                # **Retomada:** o `last_pk` avança mesmo na linha recusada, e o
                # checkpoint com ela. Uma retomada (`RESUME=1`, o padrão) NÃO
                # revisita a recusada — o que é o certo, porque ela seria
                # recusada de novo pelo mesmo motivo. Depois de corrigir a
                # causa, é `RESUME=0` que relê a origem inteira; a idempotência
                # vem do de-para, e a recusada não tem entrada lá.
                begin
                  record = converter.write!(row, com_referencias_em_linha(converter, row))
                rescue ActiveRecord::RecordInvalid => e
                  rejected.concat(rejections_for(klass, pk, e.record))
                  next
                end

                IdMap.record!(source_table: klass.source_table, legacy_pk: pk,
                              target_table: record.class.table_name, ai9_id: record.id, run_id: run_id)
                mapped[pk.to_i] = record.id
                batch_written += 1
              end

              checkpoint.advance!(last_pk: last_pk, processed: batch.size,
                                  written: batch_written, skipped: batch_skipped)
            end
          end

          written += batch_written
          skipped += batch_skipped
        end

        checkpoint.finish!

        @rejections.concat(rejected)
        rejected_rows = rejected.map(&:legacy_pk).uniq.size

        io.puts format('  %<icon>s %-26<name>s lidas %<r>5d · gravadas %<w>5d · já mapeadas %<s>5d%<rej>s',
                       icon: rejected_rows.zero? ? '+' : 'R', name: klass.converter_name,
                       r: read, w: written, s: skipped,
                       rej: rejected_rows.zero? ? '' : " · RECUSADAS #{rejected_rows}")

        rejection_section(klass, rejected) if rejected.any?

        unknown = converter.unknown_attributes
        if unknown.any?
          report.section("Colunas de destino ainda inexistentes — #{klass.converter_name}", severity: :warn) do |lines|
            unknown.each { |u| lines << "- `#{u}` ignorada (a fatia dona ainda não criou a coluna)" }
          end
        end

        Converters::Base::Outcome.new(converter: klass.converter_name, status: :loaded,
                                      read: read, written: written, skipped: skipped,
                                      orphans: scan.orphan_total, anomalies: scan.anomaly_total,
                                      unknown_attributes: unknown, rejected: rejected_rows)
      end

      # ------------------------------------------------------------- pós-carga

      # ========================================================================
      # O GANCHO QUE EXISTIA E NINGUÉM CHAMAVA.
      # ========================================================================
      #
      # Quatro conversores (`RiskControls`, `RiskEntries`, `RiskMovementTypes`,
      # `RiskOperationSubtypes`) definem `post_load!` desde `cf84f5bf6`, e **nada
      # o invocava**. O único chamador em toda a árvore era um spec, que o
      # executava na mão — e por isso ele passava, provando que o método funciona
      # e nada sobre ele acontecer numa carga.
      #
      # **Por que ficou órfão:** o gancho foi inventado pela fatia dona dos
      # conversores (S5/S11) e o motor é de outra fatia (S14). Nenhum `tasks.md`
      # e nenhuma linha de `load_order.yml` declarava o contrato entre as duas,
      # então não havia onde a lacuna aparecesse — é o mesmo padrão da DEC-127
      # ("decisão registrada não é decisão implementada") um nível acima: método
      # escrito não é método chamado.
      #
      # **Consequência medida:** o `is_default_for_type` da DEC-67 nunca foi
      # marcado numa carga real. O legado escolhia o subtipo com
      # `pluck(:id).first` sem `order`, e a coluna existe para tornar essa
      # escolha explícita; sem o gancho ela ficava `false` em TODA linha, e a
      # tela não teria subtipo padrão nenhum.
      #
      # Roda **por conversor, logo depois das linhas dele**, e não no fim da
      # execução, porque é isso que cada implementação assume: quem precisa do
      # menor `legacy_id` do tipo precisa de todas as linhas DAQUELE conversor, e
      # não das dos seguintes. E só no modo `:load` — o gancho escreve.
      def run_post_load!(converter_class)
        return unless converter_class.respond_to?(:post_load!)

        resultado = converter_class.post_load!
        report.section("Passo pós-carga — `#{converter_class.converter_name}`", severity: :info) do |out|
          out << 'Gancho `post_load!` do conversor, chamado pelo motor depois de as linhas entrarem.'
          out << ''
          Hash(resultado).each { |chave, valor| out << "- **#{chave}**: #{format_post_load_value(valor)}" }
          out << '- (o conversor não devolveu nada)' if Hash(resultado).empty?
        end
      rescue StandardError => e
        # Levantar aqui **reprova** a carga sem interromper os conversores
        # seguintes — mesma escolha das linhas recusadas, pela mesma razão.
        report.section("Passo pós-carga FALHOU — `#{converter_class.converter_name}`", severity: :reject) do |out|
          out << "- `#{e.class}`: #{e.message.lines.first.to_s.strip}"
          out << '- as linhas entraram, mas o ajuste pós-carga NÃO aconteceu.'
        end
      end

      def format_post_load_value(valor)
        case valor
        when Array then valor.empty? ? '(vazio)' : valor.map { |v| "`#{v}`" }.join(', ')
        else valor.to_s
        end
      end

      # ------------------------------------------------------- linhas recusadas

      # Uma `Rejection` por MOTIVO. Uma linha reprovada em dois campos aparece
      # duas vezes aqui e **uma** vez na contagem de linhas — é o que deixa o
      # resumo agrupar por causa sem inflar a contagem de linhas perdidas.
      # ⚠ `errors.objects`, **NUNCA** `errors.to_a`: `to_a` é apelido de
      # `full_messages`, que monta a frase inteira e, em validador customizado
      # que interpola `%{value}`, **imprime o valor recusado** — dado real de
      # cliente no relatório, contra a DEC-123. `objects` devolve os
      # `ActiveModel::Error`, de onde saem só `attribute` e `message`.
      def rejections_for(klass, legacy_pk, record)
        erros = record.respond_to?(:errors) ? record.errors.objects : []
        return [rejection(klass, legacy_pk, :base, 'inválido, sem detalhe de validação')] if erros.empty?

        erros.map { |e| rejection(klass, legacy_pk, e.attribute, e.message) }
      end

      def rejection(klass, legacy_pk, attribute, message)
        Rejection.new(source_table: klass.source_table, target_model: klass.target_model,
                      legacy_pk: legacy_pk, attribute: attribute.to_s, message: message.to_s)
      end

      # Uma seção `:reject` POR CONVERSOR, com o id de cada linha que ficou de
      # fora. É o que permite ir direto à linha na origem.
      def rejection_section(klass, rejected)
        linhas = rejected.group_by(&:legacy_pk)
        titulo = "Linhas RECUSADAS por validação — `#{klass.converter_name}` — #{linhas.size}"
        report.section(titulo, severity: :reject) do |out|
          out << "Origem `#{klass.source_table}` → destino `#{klass.target_model}`. Estas linhas " \
                 '**não entraram** no destino; a carga seguiu para revelar todos os casos (DEC-127).'
          out << ''
          out << 'Só id, coluna e mensagem de validação — nunca o valor (DEC-123).'
          out << ''
          linhas.first(200).each do |pk, itens|
            out << "- `#{klass.source_table}`##{pk}: " +
                   itens.map { |i| "`#{i.attribute}` #{i.message}" }.join(' · ')
          end
          out << "- … (#{linhas.size - 200} outra(s) linha(s) recusada(s), no resumo por causa)" if linhas.size > 200
        end
      end

      # O entregável que a DEC-127 pede: **todos** os casos de uma vez, agrupados
      # por causa. Uma execução passa a responder "o que falta consertar?" em vez
      # de "qual é o próximo defeito?".
      def rejection_summary_section
        if @rejections.empty?
          report.section('Linhas recusadas por validação — resumo por causa', severity: :info) do |out|
            out << '- nenhuma linha recusada nesta execução: tudo que foi lido e não estava'
            out << '  no de-para entrou no destino.'
          end
          return
        end

        por_causa = @rejections.group_by(&:cause)
        total_linhas = @rejections.map { |r| [r.source_table, r.legacy_pk] }.uniq.size

        report.section("Linhas recusadas por validação — RESUMO POR CAUSA — #{total_linhas} linha(s)",
                       severity: :reject) do |out|
          out << "**#{total_linhas} linha(s) da origem não entraram no destino**, por " \
                 "#{por_causa.size} causa(s) distinta(s)."
          out << ''
          out << '| linhas | causa | ids na origem (10 primeiros) |'
          out << '| ---: | --- | --- |'
          por_causa.sort_by { |_causa, itens| -itens.map(&:legacy_pk).uniq.size }.each do |causa, itens|
            ids = itens.map(&:legacy_pk).uniq
            out << "| #{ids.size} | #{causa} | #{ids.first(10).join(', ')}#{ids.size > 10 ? ', …' : ''} |"
          end
          out << ''
          out << 'Cada causa acima é **um** conserto — de conversor, de migration ou de decisão —'
          out << 'e todas apareceram na MESMA execução. Era esta a diferença que a DEC-127 pediu.'
        end
      end

      # SEGUNDO PASSO — as referências que fecham ciclo.
      #
      # `users.default_project_id` aponta para `projects`, que aponta para `segments`,
      # que aponta de volta para `users`. Não existe ordem de carga que resolva isso
      # numa passada só. O ETL de 2021 "resolveu" forçando um id fixo (BE-452 (a)); aqui
      # a linha entra sem a referência e o segundo passo a preenche pelo de-para.
      # Resolve **em linha** as referencias diferidas cujo alvo JA esta no de-para.
      #
      # ## Por que isto existe (DEC-131)
      #
      # `resolve_deferred!` roda ao FIM da carga. Ate la, toda linha com referencia
      # diferida entra com a coluna **nula** — e isso quebra qualquer indice unico
      # parcial cujo predicado dependa dessa coluna.
      #
      # Foi exatamente o que derrubou `availability_templates`:
      # `index_availability_templates_unique_root_title` e
      # `WHERE parent_template_id IS NULL AND title <> ''`. Com a hierarquia diferida,
      # **todas as 2.705 linhas parecem raiz** durante a carga. Medido na origem: entre
      # raizes reais ha **0** colisoes; com todas como raiz, ha **1** — e essa uma
      # matava a execucao inteira.
      #
      # ## Por que o segundo passo CONTINUA existindo
      #
      # Isto e otimizacao, nao substituicao. Ha ciclos que nenhuma ordem de leitura
      # resolve (`users.default_project_id` -> `projects.user_id`), e um dump futuro
      # pode trazer o pai depois do filho. O que nao resolver aqui, `resolve_deferred!`
      # resolve la — so mais tarde.
      #
      # Neste dump as tres colunas diferidas de `availability_templates` apontam, em
      # **100% das linhas**, para ids MENORES: lendo em ordem de pk, o alvo ja foi
      # mapeado, e a coluna nasce preenchida.
      def com_referencias_em_linha(converter, row)
        atributos = converter.convert(row)
        diferidas = converter.class.deferred
        return atributos if diferidas.empty?

        diferidas.each do |coluna, (tabela_ref, coluna_ref)|
          next if atributos.key?(coluna.to_sym) || atributos.key?(coluna)

          bruto = row[coluna_ref]
          next if bruto.nil? || bruto.to_s.empty?

          resolvido = IdMap.resolve(tabela_ref, bruto)
          atributos[coluna.to_sym] = resolvido if resolvido
        end

        atributos
      end

      def resolve_deferred!
        touched = Hash.new(0)
        pipeline.each do |klass|
          deferred = klass.deferred
          next if deferred.empty? || klass.missing_models.any? || !source.table?(klass.source_table)

          source.ordered_rows(klass.source_table, pk: klass.legacy_pk).each do |row|
            ai9_id = IdMap.resolve(klass.source_table, row[klass.legacy_pk])
            next if ai9_id.nil?

            updates = deferred.filter_map do |target_column, (ref_table, ref_column)|
              resolved = IdMap.resolve(ref_table, row[ref_column])
              resolved ? [target_column, resolved] : nil
            end.to_h
            next if updates.empty?

            klass.target_class.where(id: ai9_id).update_all(updates)
            touched[klass.converter_name] += 1
          end
        end

        report.section('Segundo passo — referências que fecham ciclo', severity: :info) do |lines|
          if touched.empty?
            lines << '- nenhuma referência diferida a resolver nesta origem'
          else
            touched.each { |name, n| lines << "- `#{name}`: #{n} registro(s) com referência preenchida no 2º passo" }
          end
          lines << ''
          lines << 'Existe porque `users.default_project_id` -> `projects` -> `segments` -> `users` é um'
          lines << 'CICLO. O ETL de 2021 o resolvia forçando um id fixo (BE-452 (a)), e esses registros'
          lines << 'estão em produção com autoria errada por construção.'
        end
      end

      # --------------------------------------------------------- de-para de FK

      # Chamado pelos conversores via `ref`. Conta resolvidas e órfãs (tarefa 7.4).
      def resolve_reference(source_table, legacy_pk)
        key = source_table.to_s
        cache = (@id_cache[key] ||= IdMap.cache_for(source_table))
        found = cache[legacy_pk.to_i]

        # Auto-referência (`manager_id`, `original_id`, `pair_id`) aponta para linha
        # gravada NESTA execução, depois do cache ter sido carregado. Uma consulta a
        # mais é barata; um `nil` aqui viraria órfã inventada.
        if found.nil?
          found = IdMap.resolve(key, legacy_pk)
          cache[legacy_pk.to_i] = found if found
        end

        found ? @resolved[key] += 1 : @unresolved[key] += 1
        found
      end

      # Conjunto de PKs existentes na ORIGEM — é contra ele que se conta órfão, e não
      # contra o de-para (que está vazio antes da primeira carga).
      def source_pks(table)
        @pk_cache[table.to_s] ||= (source.pks(table.to_s) if source.table?(table))
      end

      # ----------------------------------------------------------------- seções

      def relink_section
        report.section('Referências religadas pelo de-para', severity: :info) do |lines|
          keys = (@resolved.keys + @unresolved.keys).uniq.sort
          if keys.empty?
            lines << '- nenhuma referência resolvida nesta execução'
          else
            keys.each do |k|
              lines << "- `#{k}`: #{@resolved[k]} resolvida(s), #{@unresolved[k]} sem correspondência (contadas como órfãs, nunca inventadas)"
            end
          end
        end
      end

      def summary_section(outcomes)
        report.section('Resumo por conversor', severity: :info) do |lines|
          lines << '| conversor | estado | lidas | gravadas | já mapeadas | RECUSADAS | órfãs | anomalias |'
          lines << '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |'
          outcomes.each do |o|
            lines << "| `#{o.converter}` | #{o.status} | #{o.read} | #{o.written} | #{o.skipped} | " \
                     "#{o.rejected.zero? ? '—' : "**#{o.rejected}**"} | #{o.orphans} | #{o.anomalies} |"
          end
          skipped = outcomes.select { |o| o.status == :skipped }
          next if skipped.empty?

          lines << ''
          lines << "**#{skipped.size} conversor(es) pulado(s)** — o model de destino ainda não existe."
          skipped.each { |o| lines << "- `#{o.converter}`: #{o.message}" }
        end
      end

      # Registra uma família de anomalias e decide se ela aborta. É o portão de 5.4.
      def record_anomaly_group(key:, title:, lines:)
        return if lines.empty?

        authorization = decisions.describe(key)
        severity = authorization ? :warn : :abort
        report.section("#{title} — #{lines.size}", severity: severity) do |out|
          out << "Chave de decisão: `#{key}`"
          out << (if authorization
                    "**#{authorization}**"
                  else
                    '**SEM DECISÃO REGISTRADA — ABORTA.** ' \
                                                                             'Registre em `db/etl/decisions.yml` com a chave acima, ou resolva na origem.'
                  end)
          out << ''
          out.concat(lines.first(200))
          out << "- … (#{lines.size - 200} outras)" if lines.size > 200
        end
      end
    end
  end
end
