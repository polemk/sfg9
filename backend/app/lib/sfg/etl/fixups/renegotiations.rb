# frozen_string_literal: true

module Sfg
  module Etl
    module Fixups
      # FIXUPS PÓS-CARGA DA RENEGOCIAÇÃO — S9, tarefas 5.4 e 5.5 (**OPS-197**).
      #
      # ==========================================================================
      # Substitui as três rotinas de `rails c` do legado, que liam a base inteira
      # para a memória e gravavam sem particionamento nenhum.
      # ==========================================================================
      #
      # No legado elas eram método de classe colado no console
      # (`renegotiation.rb:295-313`, `renegotiation_installment.rb:265-280`,
      # `renegotiation_payment.rb:23-27`), todas no mesmo molde:
      #
      #     Renegotiation.all.each { |rn| rn.update_values! }
      #     RenegotiationInstallment.all.each { |ri| ri.update_values! }
      #     RenegotiationPayment.all.each { |rp| rp.save }
      #
      # `.all.each` materializa **a tabela inteira** antes da primeira gravação —
      # com 5.124 parcelas e 1.230 pagamentos de produção passa; numa base que
      # cresceu, não. E cada `save` desses reentrava na cascata de `after_save`
      # (BE-220), então uma passada renumerava e recalculava a mesma renegociação
      # uma vez **por parcela**.
      #
      # Aqui: `find_each` em lotes, **uma** transação por renegociação, **um**
      # recálculo de agregado por renegociação, e nenhum broadcast (ninguém está
      # com a tela aberta durante um fixup de carga).
      #
      # --------------------------------------------------------------------------
      # AS QUATRO ETAPAS, E O QUE CADA UMA CONSERTA
      # --------------------------------------------------------------------------
      #
      # * **`company`** — empresa padrão para projeto sem empresa.
      # * **`renumber`** — ordinais de parcela (por vencimento) e de pagamento
      #   (por criação), com `update_all` e **sem callbacks**.
      # * **`recalculate`** — pagamento → parcela → agregado, nessa ordem.
      # * **`counters`** — `attachments_count` reconciliado contra as linhas de
      #   fato migradas. **É a tarefa 5.4.**
      #
      # --------------------------------------------------------------------------
      # UM DESVIO DELIBERADO DO LEGADO, E ELE EVITA PERDA DE DADO
      # --------------------------------------------------------------------------
      #
      # `Renegotiation.fix_renegotiations_without_company` (`:295-305`) termina com
      #
      #     p.renegotiations.update_all(company_id: c.id)
      #
      # **sem nenhuma condição**: toda renegociação do projeto passa a apontar para
      # a primeira empresa dele, inclusive as que já tinham a empresa CERTA. Numa
      # rotina chamada "corrigir as *sem* empresa", isso reescreve as com empresa.
      # Aqui só o que está errado é tocado, e a razão é a exceção (1) do **DEC-30**:
      # replicar protege número que o cliente já vê, não produz dado errado num
      # banco novo.
      #
      # Em produção o caso é hipotético e isso está **medido**: as 169
      # renegociações do dump têm `company_id` preenchido, 0 nulo. A etapa existe
      # porque no ai9 `company_id` é `null: false` — sem empresa a linha nem entra,
      # e é melhor a carga achar a empresa pronta do que abortar por ela.
      #
      # --------------------------------------------------------------------------
      # IDEMPOTÊNCIA, LOTES E RETOMADA
      # --------------------------------------------------------------------------
      #
      # Toda etapa **deriva do estado atual**: rodar duas vezes produz o mesmo
      # resultado, e a segunda passada não encontra nada para mudar — que é como o
      # relatório prova a idempotência, e não por promessa.
      #
      # A retomada é por **pulo**, não por checkpoint: uma renegociação que já está
      # coerente é reconhecida e não regravada. Matar o processo no meio e rodar de
      # novo custa a leitura, não a escrita. O `after:` (`AFTER=<uuid>`) existe para
      # a retomada dura, e o `Checkpoint` guarda o progresso da execução.
      #
      # O padrão é **ensaio** (`dry_run: true`): ele reconcilia e relata **antes**
      # de qualquer escrita. `DRY_RUN=0` aplica.
      class Renegotiations
        STEPS = %w[company renumber recalculate counters].freeze

        DEFAULT_COMPANY_TITLE = 'Empresa Padrão'

        def initialize(dry_run: true, batch_size: 500, run_id: 'default', only: nil,
                       after: nil, report: nil, io: $stdout)
          @dry_run = dry_run
          @batch_size = [batch_size.to_i, 1].max
          @run_id = run_id
          @only = Array(only).map(&:to_s).presence
          @after = after.presence
          @report = report || Report.new('renegotiation_fixups', io: io)
          @io = io
          @counts = Hash.new(0)
        end

        attr_reader :report, :io, :batch_size, :run_id, :counts

        def dry_run? = @dry_run

        def steps
          return STEPS if @only.nil?

          STEPS.select { |s| @only.include?(s) }
        end

        def run!
          report.meta('modo', dry_run? ? 'ensaio (reconcilia, NÃO grava)' : 'aplicando')
          report.meta('lote', batch_size)
          report.meta('execução (run_id)', run_id)
          report.meta('etapas', steps.join(', '))
          report.meta('renegociações no destino', ::Renegotiation.count)

          steps.each { |step| public_send(:"step_#{step}!") }
          summary_section
          report
        end

        # ------------------------------------------------------------- company
        #
        # Garante que todo projeto tenha empresa, e que a empresa de cada
        # renegociação seja **do próprio projeto**. A segunda metade é o contrato
        # C1 aplicado ao dado: empresa de outro projeto numa renegociação é
        # vazamento de escopo gravado em coluna.
        def step_company!
          sem_empresa = ::Project.where.missing(:companies).order(:id).to_a
          criadas = []

          sem_empresa.each do |project|
            criadas << project.id
            next if dry_run?

            ::Company.create!(project: project, title: DEFAULT_COMPANY_TITLE)
          end

          trocadas = repair_cross_project_companies

          @counts[:companies_created] = criadas.size
          @counts[:companies_repaired] = trocadas.size

          severity = (criadas + trocadas).empty? ? :ok : :warn
          report.section("Empresa padrão — #{criadas.size} projeto(s) sem empresa, " \
                         "#{trocadas.size} renegociação(ões) com empresa de outro projeto",
                         severity: severity) do |lines|
            lines << "- título usado: `#{DEFAULT_COMPANY_TITLE}` (o mesmo de `renegotiation.rb:298`)"
            lines << '- **desvio declarado:** o legado fazia `p.renegotiations.update_all(company_id:)` sem'
            lines << '  condição, reescrevendo a empresa CERTA das demais. Aqui só o que está errado é tocado.'
            criadas.first(40).each do |id|
              lines << "- projeto `#{id}` #{dry_run? ? 'receberia' : 'recebeu'} empresa padrão"
            end
            trocadas.first(40).each { |linha| lines << linha }
          end
        end

        # ------------------------------------------------------------ renumber
        #
        # Só o ordinal. `update_all`, sem callbacks — renumerar não é evento de
        # negócio e passar por `save` faria a trilha registrar N versões que não
        # dizem nada (OPS-195).
        def step_renumber!
          tocadas = 0
          pagamentos = 0

          each_renegotiation do |renegotiation|
            next if dry_run?

            renegotiation.transaction do
              tocadas += ::Renegotiations::RenumberInstallments.call(renegotiation)
              renegotiation.installments.each do |installment|
                pagamentos += ::Renegotiations::RenumberPayments.call(installment)
              end
            end
          end

          fora_de_ordem = out_of_order_counts

          @counts[:installments_renumbered] = tocadas
          @counts[:payments_renumbered] = pagamentos

          report.section("Renumeração — #{fora_de_ordem[:installments]} parcela(s) e " \
                         "#{fora_de_ordem[:payments]} pagamento(s) com ordinal fora de ordem",
                         severity: fora_de_ordem.values.sum.zero? ? :ok : :warn) do |lines|
            lines << '- parcela numera por **vencimento**; pagamento, por **criação** (não pela data do'
            lines << '  pagamento — com data editável, D-B12, as duas ordens divergem e o número que o'
            lines << '  operador já viu na tela é o de criação).'
            lines << '- `update_all` em uma consulta por coleção, **sem callbacks** (OPS-195).'
            lines << (dry_run? ? '- ensaio: nada foi gravado.' : "- gravado: #{tocadas} parcela(s), #{pagamentos} pagamento(s).")
          end
        end

        # ----------------------------------------------------------- recalculate
        #
        # A cadeia inteira, na ordem do legado e **uma vez** por renegociação:
        # pagamento (`days_late`, `total_paid_value`) → parcela (mora, total, pago,
        # saldo, `is_paid`) → agregado (os ~20 campos).
        def step_recalculate!
          divergentes = []
          gravadas = 0
          ultimo = nil

          each_renegotiation do |renegotiation|
            ultimo = renegotiation.id
            mudou = recalculate_one(renegotiation)
            next if mudou.blank?

            divergentes << "- `Renegotiation` #{rotulo(renegotiation)}: #{mudou.join(', ')}"
            gravadas += 1
          end

          @counts[:recalculated] = gravadas
          @counts[:last_id] = ultimo

          report.section("Recálculo geral — #{gravadas} renegociação(ões) " \
                         "#{dry_run? ? 'divergente(s)' : 'regravada(s)'} de #{::Renegotiation.count}",
                         severity: gravadas.zero? ? :ok : :warn) do |lines|
            lines << "- `find_each` em lotes de #{batch_size}, **uma** transação e **um** recálculo de"
            lines << '  agregado por renegociação. O legado fazia `.all.each` e reentrava na cascata uma'
            lines << '  vez por parcela (BE-220).'
            lines << '- sem broadcast: ninguém está com a tela aberta durante um fixup de carga.'
            lines << "- retomada dura: `AFTER=#{ultimo}` continua da próxima." if ultimo
            divergentes.first(60).each { |l| lines << l }
            lines << "- … (#{divergentes.size - 60} outras)" if divergentes.size > 60
          end
        end

        # ------------------------------------------------------------- counters
        #
        # **TAREFA 5.4** — `attachments_count` preenchido e **conferido**.
        #
        # No legado a coluna nasce NULL (é o que o dump mostra: 134 das 169
        # renegociações de produção com `attachments_count` nulo) e `nil > 0`
        # derrubava o detalhe com `NoMethodError` (**DB-195**). No ai9 ela é
        # `null: false, default: 0` com `counter_cache` — o que falta é provar que
        # o número bate com as linhas que de fato chegaram.
        def step_counters!
          erradas = []
          total_anexos = ::RenegotiationAttachment.count

          each_renegotiation do |renegotiation|
            real = ::RenegotiationAttachment.where(renegotiation_id: renegotiation.id).count
            next if renegotiation.attachments_count == real

            erradas << "- `Renegotiation` #{rotulo(renegotiation)}: contador #{renegotiation.attachments_count} " \
                       "× #{real} anexo(s) de fato"
            next if dry_run?

            ::Renegotiations::AttachmentService.reset_counter!(renegotiation)
          end

          @counts[:counters_fixed] = erradas.size

          report.section("`attachments_count` — #{erradas.size} contador(es) fora do real, " \
                         "#{total_anexos} anexo(s) no destino",
                         severity: erradas.empty? ? :ok : :warn) do |lines|
            lines << '- DB-195: no legado a coluna nasce NULL e `nil > 0` derrubava o detalhe com'
            lines << '  `NoMethodError`. Aqui ela é `null: false, default: 0` com `counter_cache`.'
            lines << '- conferência: contador × `COUNT(*)` das linhas de anexo de fato migradas.'
            erradas.first(60).each { |l| lines << l }
            lines << "- … (#{erradas.size - 60} outros)" if erradas.size > 60
            lines << (dry_run? ? '- ensaio: nada foi gravado.' : '- reconciliado por `reset_counters`.')
          end
        end

        private

        # ---------------------------------------------------------------- laços

        # O laço de todas as etapas. `find_each` ordena pela PK e lê em lotes —
        # nunca materializa a tabela.
        def each_renegotiation(&block)
          # Sem `order(:id)` explícito: `find_each` **já** varre pela PK em ordem
          # crescente, e um `order` no escopo só faria o Rails avisar que o ignorou.
          scope = ::Renegotiation.all
          scope = scope.where(::Renegotiation.arel_table[:id].gt(@after)) if @after

          # **O checkpoint só nasce fora do ensaio.** `Checkpoint.for` é
          # `find_or_create_by!`: criá-lo no ensaio seria a única escrita de um
          # modo que promete não escrever — e "quase nada" não é nada.
          checkpoint = (Checkpoint.for(run_id: run_id, source_table: 'fixups:renegotiations') unless dry_run?)

          lidas = 0
          scope.find_each(batch_size: batch_size) do |renegotiation|
            lidas += 1
            block.call(renegotiation)
          end
          checkpoint&.update!(processed_count: lidas, state: 'done')
          lidas
        end

        def rotulo(renegotiation)
          renegotiation.legacy_id ? "legado ##{renegotiation.legacy_id}" : renegotiation.id
        end

        # -------------------------------------------------------------- company

        def repair_cross_project_companies
          fora = ::Renegotiation
                 .joins(:company)
                 .where('companies.project_id <> renegotiations.project_id')
                 .order(:id)

          fora.map do |renegotiation|
            correta = ::Company.where(project_id: renegotiation.project_id).order(:created_at, :id).first
            correta ||= unless dry_run?
                          ::Company.create!(project_id: renegotiation.project_id,
                                            title: DEFAULT_COMPANY_TITLE)
                        end

            unless dry_run? || correta.nil?
              renegotiation.update_columns(company_id: correta.id, updated_at: Time.current)
            end

            "- `Renegotiation` #{rotulo(renegotiation)}: empresa era de outro projeto " \
              "#{dry_run? ? '(seria trocada)' : "-> `#{correta&.id}`"}"
          end
        end

        # ------------------------------------------------------------- renumber

        # Conta quem está fora de ordem SEM gravar — é o que o ensaio relata e o
        # que, depois da aplicação, tem de dar zero.
        def out_of_order_counts
          parcelas = 0
          pagamentos = 0

          ::Renegotiation.find_each(batch_size: batch_size) do |renegotiation|
            esperado = ::RenegotiationInstallment
                       .where(renegotiation_id: renegotiation.id)
                       .order(due_date: :asc, created_at: :asc, id: :asc).pluck(:id, :number)
            parcelas += esperado.each_with_index.count { |(_id, numero), i| numero != i + 1 }

            esperado.each do |(installment_id, _n)|
              numeros = ::RenegotiationPayment
                        .where(renegotiation_installment_id: installment_id)
                        .order(created_at: :asc, id: :asc).pluck(:payment_number)
              pagamentos += numeros.each_with_index.count { |numero, i| numero != i + 1 }
            end
          end

          { installments: parcelas, payments: pagamentos }
        end

        # ----------------------------------------------------------- recalculate

        # Recalcula UMA renegociação e devolve a lista de campos que mudaram
        # (vazia = já estava coerente, e é assim que a retomada "por pulo"
        # funciona).
        #
        # **No ensaio a gravação ACONTECE e é revertida** (`ActiveRecord::Rollback`)
        # em vez de ser pulada. É a diferença entre reconciliar e adivinhar: o
        # agregado é derivado das parcelas JÁ recalculadas, então pular a gravação
        # das parcelas faria o ensaio comparar o agregado novo com parcelas velhas
        # e sub-relatar a divergência. A regra do ETL é *"dry-run que reconcilia
        # antes de escrever"*, e reconciliar exige calcular sobre o estado final.
        def recalculate_one(renegotiation)
          mudou = []

          renegotiation.transaction do
            renegotiation.installments.order(:due_date, :id).each do |installment|
              mudou.concat(recalculate_payments(installment))
              mudou.concat(recalculate_installment(installment))
            end

            mudou.concat(recalculate_aggregate(renegotiation))
            raise ActiveRecord::Rollback if dry_run?
          end

          mudou.uniq
        end

        def recalculate_payments(installment)
          mudou = []
          ::RenegotiationPayment.where(renegotiation_installment_id: installment.id)
                                .order(:created_at, :id).each do |payment|
            derivados = ::Renegotiations::Formulas.payment(
              date: payment.date, due_date: installment.due_date,
              installment_paid_value_with_interest_cm: payment.installment_paid_value_with_interest_cm,
              late_payment_value: payment.late_payment_value
            )
            payment.assign_attributes(derivados)
            next unless payment.changed?

            mudou.concat(payment.changed.map { |c| "pagamento.#{c}" })
            payment.save!
          end
          mudou
        end

        def recalculate_installment(installment)
          somas = ::Renegotiations::RecalculateInstallment.payment_sums(installment)
          derivados = ::Renegotiations::Formulas.installment(
            main_value: installment.main_value, interest_value: installment.interest_value,
            monetary_correction_value: installment.monetary_correction_value,
            late_payment_value: somas[:late_payment_value], paid_value: somas[:total_paid_value]
          )
          installment.assign_attributes(derivados)
          return [] unless installment.changed?

          campos = installment.changed.map { |c| "parcela.#{c}" }
          installment.save!
          campos
        end

        def recalculate_aggregate(renegotiation)
          valores = ::Renegotiations::AggregateService.compute(renegotiation)
          renegotiation.assign_attributes(
            ::Renegotiations::AggregateService::PERSISTED_FIELDS.index_with { |campo| valores[campo] }
          )
          return [] unless renegotiation.changed?

          campos = renegotiation.changed.dup
          renegotiation.save!
          campos
        end

        # --------------------------------------------------------------- resumo

        def summary_section
          report.section('Resumo dos fixups', severity: :info) do |lines|
            lines << "- empresas padrão criadas: #{counts[:companies_created]}"
            lines << "- renegociações com empresa de outro projeto: #{counts[:companies_repaired]}"
            lines << "- parcelas renumeradas: #{counts[:installments_renumbered]}"
            lines << "- pagamentos renumerados: #{counts[:payments_renumbered]}"
            lines << "- renegociações recalculadas: #{counts[:recalculated]}"
            lines << "- contadores de anexo corrigidos: #{counts[:counters_fixed]}"
            lines << ''
            lines << if dry_run?
                       '**ENSAIO.** Nada foi gravado. Rode com `DRY_RUN=0` para aplicar — ' \
                         'e a segunda passada tem de sair com tudo em zero.'
                     else
                       '**APLICADO.** Rode de novo: por serem derivações do estado atual, ' \
                         'a segunda passada tem de sair com tudo em zero. É assim que a ' \
                         'idempotência se prova.'
                     end
          end
        end
      end
    end
  end
end
