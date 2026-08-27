# frozen_string_literal: true

module Sfg
  module Etl
    module Parity
      # PARIDADE NUMÉRICA DA RENEGOCIAÇÃO — S9, tarefa 5.7.
      #
      # ==========================================================================
      # O DUMP DE PRODUÇÃO COMO ORÁCULO. É a única prova possível sem carga.
      # ==========================================================================
      #
      # A S9 fechou com a 5.7 aberta e o motivo escrito: *"exige um banco de
      # produção do legado, que não existe neste ambiente"*. **Isso deixou de ser
      # verdade em 26/08/2026** — `sfg-31-may-25.sql` tem 169 renegociações, 5.124
      # parcelas e 1.230 pagamentos, com os ~20 agregados **já gravados pelo
      # legado**.
      #
      # E a **DEC-102 continua respeitada**: nada aqui escreve no banco. A conta é
      # feita em memória, a partir do texto do dump, e comparada com o que o legado
      # gravou. Adiar a CARGA não é adiar a CONFERÊNCIA.
      #
      # O método é o mesmo que a S6 usou para os recebíveis: rodar
      # `::Renegotiations::Formulas` — o **mesmo** código que o ai9 usa para gravar
      # — sobre as linhas de produção e comparar coluna a coluna. Ler o legado e
      # escrever o esperado à mão só provaria que dois leitores do mesmo código
      # concordam entre si.
      #
      # --------------------------------------------------------------------------
      # AS TRÊS CLASSES DE DIVERGÊNCIA, E SÓ UMA É REGRESSÃO
      # --------------------------------------------------------------------------
      #
      # 1. **Precisão** (|Δ| <= R$ 0,01 em dinheiro, <= 0,01 p.p. em percentual).
      #    **NÃO é regressão** — DEC-02/D-104 é melhoria *declinada*: o legado
      #    trunca na 3ª casa da máscara, calcula em float e arredonda na gravação,
      #    e essa cadeia é replicada, não corrigida.
      # 2. **Tempo.** `overdue_installments`, `current_installment_value` e
      #    `current_value` dependem de *hoje*. O valor gravado em produção é
      #    fotografia do dia em que `update_values!` rodou pela última vez — que
      #    para muitas linhas é 2022. Comparar com a data de hoje mediria o
      #    calendário, não a fórmula. Ficam numa seção própria, informativa.
      # 3. **Regressão.** Fórmula que mudou, sinal que inverteu, estado que mudou
      #    de valor. É o que a tarefa 5.7 nomeia, e é o que aborta.
      #
      # A **única** mudança de valor declarada da fatia é o `state`
      # "Inconsistente" (**D-45**): no legado a linha que o escrevia era apagada
      # pela seguinte e o estado nunca chegava ao banco. Toda divergência de
      # estado que seja exatamente `<qualquer> -> Inconsistente` é contada à parte,
      # como **mudança declarada**, e não como regressão.
      #
      # --------------------------------------------------------------------------
      # DUAS COLUNAS NÃO EXISTEM EM PRODUÇÃO — E ISSO É UM ACHADO, NÃO UM AJUSTE
      # --------------------------------------------------------------------------
      #
      # `desagio_value` e `total_value_with_desagio` são criadas por
      # `20220620134050_add_discount_values_to_renegotiation`, uma das **24
      # migrations que nunca rodaram em produção** (`analise-dump-producao.md` §1).
      # Elas não estão no `CREATE TABLE public.renegotiations` do dump.
      #
      # `renegotiation.rb:113` do repositório faz
      # `self.total_value_with_desagio = self.original_value - self.desagio_value`.
      # Num banco sem essas colunas isso seria `NoMethodError`, e `update_values`
      # nunca terminaria — o que mataria junto o cron diário
      # (`CRONFacade.update_renegotiations_counters`).
      #
      # **A medição REPROVOU essa hipótese.** Os agregados gravados batem com a
      # soma das parcelas em 47.162 de 47.170 comparações, inclusive
      # `overdue_installments` na data do próprio `updated_at`. Logo o recálculo
      # estava rodando — e a conclusão é a outra: **a produção roda um commit
      # anterior a 20/06/2022**, sem a linha do deságio. O repositório está à
      # frente do que está no ar, e não só nas migrations.
      #
      # Aqui o deságio entra como zero (é o `default: 0` da migration) e as duas
      # colunas ficam fora da comparação, nomeadas.
      class Renegotiations
        # Dinheiro: um centavo. Percentual: um centésimo de ponto.
        MONEY_TOLERANCE = BigDecimal('0.01')

        # Agregados comparáveis: a fórmula os deriva só de parcela e pagamento.
        COMPARABLE = %i[
          installments_count first_due_date last_due_date correct_value
          installments_main_value installments_interest_value
          installments_main_value_with_interest installments_monetary_correction_value
          installments_main_value_with_interest_cm main_value
          paid_value_with_interest_cm pending_main_value paid_percent
          late_payment_value paid_value remaining_value
          paid_installments due_installments state
        ].freeze

        # Dependem de *hoje*. Medidos, reportados, nunca contados como regressão.
        TIME_DEPENDENT = %i[overdue_installments current_installment_value current_value].freeze

        # Criadas por migration que nunca subiu em produção.
        ABSENT_IN_PRODUCTION = %i[total_value_with_desagio].freeze

        INSTALLMENT_FIELDS = %i[
          main_value_with_interest main_value_with_interest_cm late_payment_value
          installment_total_value paid_value saldo pending_value is_paid
        ].freeze

        PAYMENT_FIELDS = %i[days_late total_paid_value].freeze

        # Uma divergência medida.
        Divergence = Struct.new(:scope, :legacy_pk, :field, :legacy, :ai9, :kind, keyword_init: true) do
          def delta
            return nil unless legacy.is_a?(BigDecimal) && ai9.is_a?(BigDecimal)

            (ai9 - legacy).abs
          end

          def to_line
            extra = delta ? " (Δ #{delta.to_s('F')})" : ''
            "- `#{scope}`##{legacy_pk} `#{field}`: legado #{format_value(legacy)} × ai9 " \
              "#{format_value(ai9)}#{extra}"
          end

          def format_value(value)
            case value
            when BigDecimal then value.to_s('F')
            when nil then '(nulo)'
            else value.to_s
            end
          end
        end

        def initialize(source:, report: nil, io: $stdout, sample: nil)
          @source = source
          @report = report || Report.new('renegotiation_parity', io: io)
          @io = io
          @sample = sample&.to_i
          @comparisons = 0
          @divergences = []
          @declared_state_changes = []
          @time_dependent = []
        end

        attr_reader :source, :report, :io, :comparisons, :divergences

        def run!
          report.meta('origem', source.describe)
          report.meta('amostra', @sample ? "as #{@sample} primeiras renegociações" : 'todas as renegociações')

          unless source.table?('renegotiations')
            missing_section
            return report
          end

          compare_all!
          precision_section
          time_section
          declared_change_section
          attachments_count_section
          regression_section
          summary_section
          report
        end

        private

        # ------------------------------------------------------------ comparação

        def compare_all!
          installments_by_renegotiation = group_installments
          payments_by_installment = group_payments

          rows = source.ordered_rows('renegotiations')
          rows = rows.first(@sample) if @sample

          rows.each do |row|
            installments = installments_by_renegotiation.fetch(row['id'].to_s, [])

            derived_installments = []
            derived_payments = []
            installments.each do |installment|
              parcela, pagamentos = compare_installment(
                installment, payments_by_installment.fetch(installment['id'].to_s, [])
              )
              derived_installments << parcela
              derived_payments.concat(pagamentos)
            end

            compare_aggregate(row, derived_installments, derived_payments)
          end
        end

        def group_installments
          return {} unless source.table?('renegotiation_installments')

          source.ordered_rows('renegotiation_installments').group_by { |r| r['renegotiation_id'].to_s }
        end

        def group_payments
          return {} unless source.table?('renegotiation_payments')

          source.ordered_rows('renegotiation_payments').group_by { |r| r['renegotiation_installment_id'].to_s }
        end

        # Uma parcela: recalcula pelos MESMOS somatórios que
        # `RecalculateInstallment#payment_sums` usa, e devolve o hash de derivados
        # que o agregado consome — assim a comparação da renegociação usa o que o
        # ai9 produziria, não o que o legado gravou.
        #
        # Devolve `[parcela_derivada, pagamentos_derivados]`. **Os pagamentos
        # derivados são o que entra no agregado** — passar as linhas cruas do dump
        # daria `nil` em toda soma, porque lá as chaves são texto.
        def compare_installment(row, payments)
          derived_payments = payments.map { |p| compare_payment(p, row) }

          mora = derived_payments.sum(BigDecimal(0)) { |p| p[:late_payment_value] }
          pago = derived_payments.sum(BigDecimal(0)) { |p| p[:total_paid_value] }

          ai9 = ::Renegotiations::Formulas.installment(
            main_value: row['main_value'], interest_value: row['interest_value'],
            monetary_correction_value: row['monetary_correction_value'],
            late_payment_value: mora, paid_value: pago
          )

          INSTALLMENT_FIELDS.each do |field|
            compare_field('renegotiation_installments', row['id'], field, row[field.to_s], ai9[field])
          end

          parcela = ai9.merge(
            due_date: to_date(row['due_date']),
            month: row['month'], year: row['year'],
            main_value: dec(row['main_value']),
            interest_value: dec(row['interest_value']),
            monetary_correction_value: dec(row['monetary_correction_value'])
          )

          [parcela, derived_payments]
        end

        def compare_payment(row, installment_row)
          ai9 = ::Renegotiations::Formulas.payment(
            date: to_date(row['date']), due_date: to_date(installment_row['due_date']),
            installment_paid_value_with_interest_cm: row['installment_paid_value_with_interest_cm'],
            late_payment_value: row['late_payment_value']
          )

          PAYMENT_FIELDS.each do |field|
            compare_field('renegotiation_payments', row['id'], field, row[field.to_s], ai9[field])
          end

          ai9.merge(
            late_payment_value: dec(row['late_payment_value']),
            installment_paid_value_with_interest_cm: dec(row['installment_paid_value_with_interest_cm'])
          )
        end

        # rubocop:disable Metrics/AbcSize
        def compare_aggregate(row, derived_installments, payments)
          # `updated_at` é o dia em que o legado gravou o agregado. É a data certa
          # para os campos que dependem de "hoje" — e mesmo ela é aproximada,
          # porque a linha pode ter sido tocada depois por outro caminho.
          today = to_date(row['updated_at']) || Date.current

          ai9 = ::Renegotiations::Formulas.aggregate(
            installments: derived_installments,
            payments: payments.map do |p|
              { installment_paid_value_with_interest_cm: p[:installment_paid_value_with_interest_cm] }
            end,
            total_debt: row['total_debt'], original_value: row['original_value'],
            # A migration do deságio nunca subiu em produção; o `default: 0` da
            # própria migration é o valor que a coluna teria.
            desagio_value: 0,
            operation_interest_rate: row['operation_interest_rate'], today: today
          )

          COMPARABLE.each do |field|
            compare_field('renegotiations', row['id'], field, row[field.to_s], ai9[field])
          end

          TIME_DEPENDENT.each do |field|
            legacy = normalize(field, row[field.to_s])
            mine = normalize(field, ai9[field])
            @comparisons += 1
            next if legacy == mine || equal_enough?(field, legacy, mine)

            @time_dependent << Divergence.new(scope: 'renegotiations', legacy_pk: row['id'], field: field,
                                              legacy: legacy, ai9: mine, kind: :time)
          end
        end
        # rubocop:enable Metrics/AbcSize

        def compare_field(scope, legacy_pk, field, legacy_raw, ai9_raw)
          legacy = normalize(field, legacy_raw)
          mine = normalize(field, ai9_raw)
          @comparisons += 1
          return if legacy == mine

          # O estado "Inconsistente" é a única mudança de VALOR declarada da fatia
          # (D-45). Ela é contada, nomeada e mantida fora da conta de regressão.
          if field == :state && mine == ::Renegotiation::STATE_INCONSISTENT
            @declared_state_changes << Divergence.new(scope: scope, legacy_pk: legacy_pk, field: field,
                                                      legacy: legacy, ai9: mine, kind: :declared)
            return
          end

          return if equal_enough?(field, legacy, mine)

          @divergences << Divergence.new(scope: scope, legacy_pk: legacy_pk, field: field,
                                         legacy: legacy, ai9: mine,
                                         kind: precision?(legacy, mine) ? :precision : :regression)
        end

        # Igualdade que não é regressão nem precisão: nulo do legado onde a
        # fórmula produz zero é ausência de gravação, não divergência de conta.
        def equal_enough?(_field, legacy, mine)
          return true if legacy.nil? && mine.is_a?(BigDecimal) && mine.zero?
          return true if legacy.nil? && mine.is_a?(Integer) && mine.zero?

          false
        end

        def precision?(legacy, mine)
          return false unless legacy.is_a?(BigDecimal) && mine.is_a?(BigDecimal)

          (mine - legacy).abs <= MONEY_TOLERANCE
        end

        # ---------------------------------------------------------- normalização

        DATE_FIELDS = %i[first_due_date last_due_date due_date].freeze
        INTEGER_FIELDS = %i[installments_count paid_installments overdue_installments
                            due_installments days_late].freeze
        BOOLEAN_FIELDS = %i[is_paid].freeze

        def normalize(field, value)
          return nil if value.nil? || (value.respond_to?(:empty?) && value.empty?)
          return to_date(value) if DATE_FIELDS.include?(field)
          return value.to_i if INTEGER_FIELDS.include?(field)
          return ::Renegotiations::Formulas.truthy?(value) if BOOLEAN_FIELDS.include?(field)
          return value.to_s if field == :state

          dec(value).round(2)
        end

        def dec(value) = ::Renegotiations::Formulas.dec(value)

        def to_date(value)
          return value if value.is_a?(Date)
          return value.to_date if value.is_a?(Time)
          return nil if value.blank?

          Date.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        # ---------------------------------------------------------------- seções

        def missing_section
          report.section('Origem sem `renegotiations` — nada a comparar', severity: :warn) do |lines|
            lines << '- a origem informada não tem a tabela. Rode com `SOURCE=dump DUMP=<pg_dump de produção>`.'
          end
        end

        def by_kind(kind) = @divergences.select { |d| d.kind == kind }

        def precision_section
          list = by_kind(:precision)
          report.section("Divergências de PRECISÃO — #{list.size} (DEC-02: melhoria declinada, não é regressão)",
                         severity: list.empty? ? :ok : :info) do |lines|
            lines << '- tolerância: R$ 0,01. A cadeia truncamento na entrada → float no cálculo →'
            lines << '  arredondamento na gravação é **replicada** (DEC-02/D-104).'
            list.first(60).each { |d| lines << d.to_line }
            lines << "- … (#{list.size - 60} outras)" if list.size > 60
          end
        end

        def time_section
          report.section("Campos que dependem de HOJE — #{@time_dependent.size} divergência(s), informativo",
                         severity: :info) do |lines|
            lines << "- comparados com `updated_at` da própria linha: #{TIME_DEPENDENT.join(', ')}."
            lines << '- o valor gravado em produção é fotografia do dia em que `update_values!` rodou pela'
            lines << '  última vez; comparar com a data de hoje mediria o calendário, não a fórmula (D-54).'
            @time_dependent.first(40).each { |d| lines << d.to_line }
            lines << "- … (#{@time_dependent.size - 40} outras)" if @time_dependent.size > 40
          end
        end

        def declared_change_section
          report.section("Mudança de estado DECLARADA (D-45) — #{@declared_state_changes.size}",
                         severity: :info) do |lines|
            lines << '- o legado escrevia o estado e a linha seguinte o sobrescrevia'
            lines << '  (`renegotiation.rb:118-123`), então "Inconsistente" nunca chegava ao banco e os dois'
            lines << '  filtros da tela ficavam inertes. É a **única** mudança de valor da fatia, e é'
            lines << '  deliberada (BE-209, golden 4.6).'
            @declared_state_changes.first(60).each { |d| lines << d.to_line }
            lines << "- … (#{@declared_state_changes.size - 60} outras)" if @declared_state_changes.size > 60
          end
        end

        # **TAREFA 5.4 medida contra produção.** `attachments_count` do legado ×
        # `COUNT(*)` das linhas de anexo, na origem. É a conferência que a carga
        # depois refaz no destino (`Sfg::Etl::Fixups::Renegotiations`, etapa
        # `counters`) — e é aqui que se descobre se o número do legado era
        # confiável antes de copiá-lo.
        def attachments_count_section
          unless source.table?('renegotiation_attachments')
            return report.section('`attachments_count` — origem sem `renegotiation_attachments`',
                                  severity: :info) do |lines|
              lines << '- nada a conferir nesta origem.'
            end
          end

          reais = source.ordered_rows('renegotiation_attachments')
                        .group_by { |r| r['renegotiation_id'].to_s }
                        .transform_values(&:size)

          nulos = []
          divergentes = []
          source.ordered_rows('renegotiations').each do |row|
            gravado = row['attachments_count']
            real = reais.fetch(row['id'].to_s, 0)
            nulos << row['id'] if gravado.nil?
            next if gravado.to_i == real

            divergentes << Divergence.new(scope: 'renegotiations', legacy_pk: row['id'],
                                          field: :attachments_count, legacy: gravado.nil? ? nil : gravado.to_i,
                                          ai9: real, kind: :counter)
          end

          report.section("`attachments_count` no legado — #{nulos.size} NULO(S), " \
                         "#{divergentes.size} fora do real de #{reais.values.sum} anexo(s)",
                         severity: divergentes.empty? ? :ok : :warn) do |lines|
            lines << '- **DB-195**: no legado a coluna nasce NULL, e `nil > 0` derrubava o detalhe com'
            lines << '  `NoMethodError`. No ai9 ela é `null: false, default: 0` — o NULO vira 0, que é o'
            lines << '  número certo para quem não tem anexo nenhum.'
            lines << "- renegociações na origem: #{source.ordered_rows('renegotiations').size}"
            lines << "- com anexo de fato: #{reais.size}; total de anexos: #{reais.values.sum}"
            divergentes.first(60).each { |d| lines << d.to_line }
            lines << "- … (#{divergentes.size - 60} outros)" if divergentes.size > 60
          end
        end

        def regression_section
          list = by_kind(:regression)
          report.section("REGRESSÕES — #{list.size} (fórmula mudada, sinal invertido ou estado com outro valor)",
                         severity: list.empty? ? :ok : :abort) do |lines|
            if list.empty?
              lines << '- nenhuma. Toda divergência tem classificação e nenhuma é mudança de fórmula.'
            else
              list.first(200).each { |d| lines << d.to_line }
              lines << "- … (#{list.size - 200} outras)" if list.size > 200
            end
          end
        end

        def summary_section
          report.section('Resumo', severity: :info) do |lines|
            lines << "- comparações: **#{@comparisons}**"
            iguais = @comparisons - @divergences.size - @declared_state_changes.size - @time_dependent.size
            lines << "- iguais: **#{iguais}**"
            lines << "- precisão (não é regressão): #{by_kind(:precision).size}"
            lines << "- mudança declarada (D-45): #{@declared_state_changes.size}"
            lines << "- regressões: **#{by_kind(:regression).size}**"
            lines << "- campos dependentes de data, fora da conta: #{@time_dependent.size}"
            lines << ''
            lines << "**Fora da comparação:** #{ABSENT_IN_PRODUCTION.join(', ')} — a migration"
            lines << '`20220620134050_add_discount_values_to_renegotiation` **nunca rodou em produção**'
            lines << '(uma das 24 de `analise-dump-producao.md` §1). A coluna não existe no dump.'
          end
        end
      end
    end
  end
end
