# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `receivable_entries` (legado) -> `ReceivableEntry` (ai9). **S6**,
      # **DB-167**, **OPS-150**.
      #
      # **A segunda maior tabela do sistema: 28.131 linhas**, de 27/02/2022 a
      # 30/05/2025. Escrito agora, antes da carga, por **DEC-102** — *"a carga
      # foi adiada, o conversor não"*.
      #
      # ## Os derivados são COPIADOS, não recalculados
      #
      # A tentação óbvia é rodar o `Receivables::Calculator` sobre cada linha e
      # gravar o resultado. **Não.** Duas razões, e as duas estão decididas:
      #
      # 1. **DEC-30** — o legado é o sistema validado. Os ~33 derivados de
      #    produção são o que o cliente viu por três anos. Recalcular
      #    substituiria dado observado por dado gerado.
      # 2. Recalcular esconderia justamente o que interessa conferir. A varredura
      #    das 28.099 linhas limpas mostrou que o motor do ai9 reproduz os 33
      #    derivados **exatamente** — 927.267 comparações, zero divergência. Esse
      #    é o resultado da **conferência**; transformá-lo em premissa da carga
      #    apagaria a conferência.
      #
      # Há **quatro** borderôs cujos `tarifas_*` estão defasados em relação às
      # próprias tarifas (21608, 21871, 21872, 26246) — o D-09 visível no dado.
      # Eles vêm **como estão**, e o relatório os nomeia.
      #
      # ## DEC-36 governa a operação de risco, e não é assunto deste conversor
      #
      # `operation_value` das operações históricas é **copiado**, não
      # recalculado (DEC-36 substitui o DEC-29). Aqui isso é automático: nenhuma
      # `RiskOperation` é criada por este conversor. Em produção **nenhum**
      # borderô jamais gerou operação — a migration que criou
      # `risk_operation_subtype_id` nunca subiu, e as duas colunas **não existem
      # no dump**. Por isso `risk_operation_type_id` e `risk_operation_subtype_id`
      # nem aparecem no `convert`.
      #
      # ## `resource_kind_id` não é convertida
      #
      # Medido: **0 de 28.131** linhas têm valor, e `resource_kinds` tem 0
      # linhas. `DB-289` é `dropped` com evidência, e a coluna não existe no ai9.
      #
      # ## Os 32 borderôs com `NaN` — RECALCULADOS pelo motor (DEC-128.3)
      #
      # Produção tem **32 linhas com `NaN`** em coluna de dinheiro ou de
      # percentual — o **D-10** materializado. O Postgres aceita `NaN` em
      # `numeric`; o `ReceivableEntry` do ai9 **não**.
      #
      # **O que está corrompido, medido coluna a coluna no dump de 31/05/2025:**
      #
      # | onde | quantas |
      # | --- | ---: |
      # | `recompra` / `retencao` / `fomento` (dedução DIGITÁVEL) | 30 |
      # | `valor_bruto` (a entrada RAIZ) | 1 |
      # | `total_deducoes`, `vlr_liq_recebido`, `*_percent`, `valor_liquido`, `tarifas_*` … (DERIVADOS) | 32 |
      #
      # Em 30 das 32 a corrupção é **uma** dedução digitável, e a origem dela é
      # conhecida: `parseFloat("")` do JavaScript da tela do legado
      # (`_body.js.erb:412-415`) devolve `NaN` para **campo em branco**, e o
      # `NaN` foi postado e gravado. Não é valor perdido — é **campo que ninguém
      # preencheu**, e o próprio servidor do legado já o tratava como zero
      # (`receivable_entry.rb:59`: `self.recompra.blank? ? 0 : …`).
      #
      # **DEC-128.3 — a decisão do usuário: recalcular pelo motor.** Diferente da
      # tarifa (DEC-120, que entra NULA), aqui recalcular **não inventa dado** —
      # restaura o que o próprio cálculo deveria ter gravado, pelo mesmo motor
      # que a tela usa (contrato **C2**, `Receivables::Calculator`). É o único
      # caminho que mantém a contagem batendo com o legado **e** os números
      # somáveis: em `float` um `NaN` contamina toda soma que o encontre.
      #
      # **Três limites, e eles importam:**
      #
      # 1. **só as colunas não finitas são substituídas.** As derivadas que
      #    chegaram íntegras continuam COPIADAS — é o DEC-30, e é o que preserva
      #    a evidência dos 4 borderôs com `tarifas_*` defasados (D-09) e das
      #    927.267 comparações que provaram o motor. Recalcular a linha inteira
      #    trocaria dado observado por dado gerado sem necessidade.
      # 2. **entrada não finita entra ZERO**, porque é o que "campo em branco"
      #    significa neste domínio e porque as colunas são `null: false` com
      #    `default 0.0`. Sai listada com o valor de origem.
      # 3. **`valor_bruto` não finito (1 linha) é OUTRA COISA** e sai com chave de
      #    decisão própria: ali não há derivado a restaurar, a raiz da conta é que
      #    se perdeu. Ver `nan_anomalies`.
      #
      # Os 32 saem **listados**, com o valor de origem e o recalculado lado a
      # lado, como a decisão pede.
      class ReceivableEntries < Base
        def self.source_table = 'receivable_entries'
        def self.target_model = 'ReceivableEntry'
        def self.owner_slice = 'S6'

        def self.references
          {
            'project_id' => 'projects',
            'company_id' => 'companies',
            'carrier_id' => 'carriers',
            'wallet_id' => 'wallets',
            'receivable_kind_id' => 'receivable_kinds',
            'resource_source_id' => 'resource_sources',
            'user_id' => 'livetat_auth_users'
          }
        end

        def self.booleans = %w[has_safegold_management]
        def self.enums = { 'status' => Values::RECEIVABLE_STATUS }
        def self.sums = %w[valor_bruto valor_liquido valor_total_tarifas vlr_liq_recebido]
        def self.year_column = 'date'

        # As colunas de dinheiro em que produção tem `NaN`. Conferidas no dump.
        NAN_SENSITIVE = %w[
          valor_bruto vlr_bruto_recusado vlr_bruto_final valor_total_tarifas valor_liquido
          calc_valor_liq_correto recompra retencao fomento outros total_deducoes vlr_liq_recebido
          tarifas_ad_valorem tarifas_desagio tarifas_iof tarifas_outras
          multiplicador_pm_empresa multiplicador_pm_float
          recompra_percent retencao_percent fomento_percent outros_percent
        ].freeze

        # As ~33 colunas derivadas, copiadas verbatim. Ver o cabeçalho.
        DERIVED = %w[
          vlr_bruto_final qtd_final float_calculado diferenca_float checagem_iof
          valor_total_tarifas valor_liquido
          recompra_percent retencao_percent fomento_percent outros_percent
          total_deducoes vlr_liq_recebido
          tarifas_ad_valorem tarifas_desagio tarifas_iof tarifas_outras
          taxa_desconto_nominal_desagio_advalorem_bancos taxa_desconto_nominal_despesas_bancos
          taxa_desconto_nominal_despesas_iof_bancos
          custo_efetivo_pz_med_banco custo_efetivo_pz_med_banco_sem_iof
          taxa_desconto_nominal_desagio_advalorem_emp taxa_desconto_nominal_despesas_emp
          taxa_desconto_nominal_despesas_iof_emp
          custo_efetivo_pz_med_emp custo_efetivo_pz_med_emp_sem_iof
          custo_efetivo_sem_float custo_efetivo_com_float_total custo_efetivo_com_float_sem_iof
          multiplicador_pm_empresa multiplicador_pm_float
          calc_valor_liq_correto dif_calc_vlr_liq
          nominal_tax_check nominal_tax_check_with_float
        ].freeze

        INTEGER_COLUMNS = %w[qtd_titulos qtd_recusada qtd_final].freeze

        # As colunas que o **usuário digita** — o `Input` do contrato C2, mais as
        # que a tela aceita e o cálculo não usa. `NaN` aqui não é derivado
        # corrompido: é campo que ninguém preencheu.
        ENTRADAS_DIGITAVEIS = %w[
          valor_bruto vlr_bruto_recusado prz_med_pond_emp prz_med_pond_bco
          float_acordado cst_efetivo_acordado nominal_tax
          recompra retencao fomento outros
        ].freeze

        # A RAIZ da conta. `NaN` nestas duas não tem recálculo possível — não há
        # de onde tirar o valor bruto de volta.
        ENTRADAS_RAIZ = %w[valor_bruto vlr_bruto_recusado].freeze

        # **DEC-117** — as 6 colunas de escala 6 são `float` no ai9, como já eram
        # no legado (`../sfg/db/migrate/20210315183541_create_receivable_entries.rb:32-38`).
        #
        # Elas são as únicas cuja fórmula legada **não arredonda** antes de
        # gravar: `recompra_percent` é `100 * (recompra / valor_liquido)` cru
        # (`../sfg/app/models/receivable_entry.rb:59`), e produção guardou
        # `19.704917111218396` — 17 dígitos significativos, que é a assinatura de
        # um `double`. Passá-las por `to_decimal` e depois por `decimal(15,6)`
        # acrescentava **um ponto de arredondamento que o legado não tinha**:
        # medido, **48 divergências em 5.321 comparações** contra o dump de
        # 31/05/2025 (`spec/lib/sfg/etl/values_precision_spec.rb`).
        #
        # As outras 19 `float` do legado continuam entrando por `to_decimal`, e
        # isso é decisão, não descuido: a fórmula delas já arredonda (`.round(2)`,
        # `.round(4)`), então o `decimal` do ai9 não introduz arredondamento novo
        # — medido, **0 divergências**.
        FLOAT_COLUMNS = %w[
          float_calculado diferenca_float
          recompra_percent retencao_percent fomento_percent outros_percent
        ].freeze

        def convert(row)
          atributos = {
            project_id: ref('projects', row['project_id']),
            company_id: ref('companies', row['company_id']),
            carrier_id: ref('carriers', row['carrier_id']),
            wallet_id: ref('wallets', row['wallet_id']),
            receivable_kind_id: ref('receivable_kinds', row['receivable_kind_id']),
            resource_source_id: ref('resource_sources', row['resource_source_id']),
            user_id: ref('livetat_auth_users', row['user_id']),

            date: row['date'],
            data_credito: row['data_credito'],
            # STRING, sempre. Produção tem `F-76`, `48-49`, `202023005-6`,
            # `1540962/20` e **669 linhas com texto vazio** — que não é NULL.
            nro_bordero: row['nro_bordero'],
            contrato: row['contrato'],
            description: row['description'],
            # DEC-52 — 379 textos de negócio vindos do importador Django que
            # nenhuma view do legado jamais mostrou. Agora têm tela.
            observacoes: row['observacoes'],
            has_safegold_management: Values.to_boolean(row['has_safegold_management']).value,

            # DEC-128.3 - entrada nao finita entra ZERO e sai LISTADA. Ver
            # `entrada_digitavel` e o cabecalho.
            valor_bruto: entrada_digitavel(row, 'valor_bruto'),
            vlr_bruto_recusado: entrada_digitavel(row, 'vlr_bruto_recusado'),
            qtd_titulos: row['qtd_titulos'].to_i,
            qtd_recusada: row['qtd_recusada'].to_i,
            prz_med_pond_emp: entrada_digitavel(row, 'prz_med_pond_emp'),
            prz_med_pond_bco: entrada_digitavel(row, 'prz_med_pond_bco'),
            float_acordado: entrada_digitavel(row, 'float_acordado'),
            cst_efetivo_acordado: entrada_digitavel(row, 'cst_efetivo_acordado'),
            nominal_tax: entrada_digitavel(row, 'nominal_tax'),
            recompra: entrada_digitavel(row, 'recompra'),
            retencao: entrada_digitavel(row, 'retencao'),
            fomento: entrada_digitavel(row, 'fomento'),
            outros: entrada_digitavel(row, 'outros'),

            # BE-445 — o texto pt-BR vira chave estável. Valor fora do de-para
            # NÃO vira `nil`: vira anomalia (tarefa F.2).
            status: Values.to_enum_key(row['status'], Values::RECEIVABLE_STATUS,
                                       table: self.class.source_table, pk: row['id'], column: 'status').value,

            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }

          DERIVED.each do |coluna|
            next if atributos.key?(coluna.to_sym)

            atributos[coluna.to_sym] = case coluna
                                       when *INTEGER_COLUMNS then row[coluna]&.to_i
                                       # DEC-117 — sem `BigDecimal` no caminho: o
                                       # dump já traz o `double` que produção gravou.
                                       when *FLOAT_COLUMNS then Values.to_float(row[coluna])
                                       else Values.to_decimal(row[coluna])
                                       end
          end

          restaurar_derivados_corrompidos!(row, atributos)
          sanear_nao_finitos!(atributos)

          atributos
        end

        # ==================================================================
        # DEC-128.3 — o recálculo. Ver o cabeçalho para o porquê e os limites.
        # ==================================================================

        # As colunas que o **usuário digita**. Não finito aqui é campo em branco
        # da tela do legado (`parseFloat("")`), e entra ZERO: é o que o próprio
        # servidor do legado fazia (`recompra.blank? ? 0`) e é o `default` da
        # coluna no ai9, que é `null: false`. Sai LISTADA com o valor de origem.
        def entrada_digitavel(row, coluna)
          bruto = Values.to_decimal(row[coluna])
          return bruto unless nao_finito?(bruto)

          BigDecimal(0)
        end

        # Substitui **apenas** os derivados não finitos pelo que o motor calcula.
        # Os íntegros continuam copiados (DEC-30) — é o que preserva a evidência
        # do D-09 e das 927.267 comparações que provaram o motor.
        def restaurar_derivados_corrompidos!(row, atributos)
          corrompidos = DERIVED.select { |coluna| nan_text?(row[coluna]) }
          return if corrompidos.empty?

          calculado = motor_c2(row, atributos)
          return if calculado.nil?

          corrompidos.each do |coluna|
            next unless calculado.key?(coluna.to_sym)

            atributos[coluna.to_sym] = if FLOAT_COLUMNS.include?(coluna)
                                         calculado[coluna.to_sym].to_f
                                       else
                                         calculado[coluna.to_sym]
                                       end
          end
        end

        # **O MESMO motor que a tela usa** (contrato C2). As tarifas vêm da
        # ORIGEM, porque `receivable_taxes` carrega DEPOIS deste conversor
        # (`load_order.yml`) — e a tarifa de valor não finito fica de fora da
        # soma, exatamente como a DEC-120 manda (`Calculator#known_taxes`).
        def motor_c2(row, atributos)
          entrada = ::Receivables::Calculator::Input.new(
            valor_bruto: atributos[:valor_bruto],
            vlr_bruto_recusado: atributos[:vlr_bruto_recusado],
            qtd_titulos: atributos[:qtd_titulos],
            qtd_recusada: atributos[:qtd_recusada],
            prz_med_pond_emp: atributos[:prz_med_pond_emp],
            prz_med_pond_bco: atributos[:prz_med_pond_bco],
            float_acordado: atributos[:float_acordado],
            cst_efetivo_acordado: atributos[:cst_efetivo_acordado],
            recompra: atributos[:recompra],
            retencao: atributos[:retencao],
            fomento: atributos[:fomento],
            outros: atributos[:outros],
            taxes: tarifas_da_origem(row['id'])
          )
          ::Receivables::Calculator.call(entrada, iof_rate: aliquota_iof(row['date']))
        rescue StandardError
          # Recálculo que levanta NÃO derruba a carga: a linha entra com o que a
          # origem tinha e a anomalia continua listada. O relatório é o
          # entregável; um `rescue` mudo aqui seria o oposto disso, e por isso a
          # linha do relatório é escrita mesmo quando o motor não responde.
          nil
        end

        # A alíquota vigente na DATA da operação (BE-160 / D-15). Sem `IofRate`
        # semeado o calculador cai nas alíquotas de origem, e isso é deliberado
        # lá: um borderô não pode deixar de ser calculável porque o seed não rodou.
        def aliquota_iof(data)
          return nil unless self.class.model_ready?('IofRate')

          ::IofRate.effective_on(data || Date.current)
        rescue StandardError
          nil
        end

        # Lido UMA vez, e **só quando há borderô corrompido** — são 58.473
        # tarifas, e montá-las para as 28.099 linhas íntegras seria trocar
        # segundos por minutos sem nenhum uso.
        def tarifas_da_origem(entry_id)
          tarifas_por_bordero[entry_id.to_s] || []
        end

        def tarifas_por_bordero
          @tarifas_por_bordero ||= begin
            tabela = 'receivable_taxes'
            linhas = run.source.table?(tabela) ? run.source.ordered_rows(tabela) : []
            linhas.group_by { |t| t['receivable_entry_id'].to_s }.transform_values do |lista|
              lista.map do |t|
                ::Receivables::Calculator::Tax.new(
                  # DEC-120 — tarifa não finita entra NULA e o motor a deixa
                  # FORA da soma. Não é o mesmo que somar zero.
                  value: Values.to_decimal_finite(t['value']),
                  is_advalorem: t['is_advalorem'], is_desagio: t['is_desagio'], is_iof: t['is_iof']
                )
              end
            end
          end
        end

        def nao_finito?(valor)
          ::Receivables::InputGuard.nonfinite?(valor)
        end

        # **A última rede: nenhum não finito chega ao banco.**
        #
        # Medido ao executar contra o dump: recalcular a linha cuja RAIZ é `NaN`
        # (`valor_bruto`, 1 de 28.131) produz `Infinity` em
        # `nominal_tax_check` — a fórmula divide por `vlr_bruto_final`, que virou
        # zero. Sem esta varredura o borderô era RECUSADO pela validação
        # `derived_values_must_be_finite` e a carga fechava 28.130/28.131.
        # Perder a linha inteira por causa de uma taxa apurada é trocar um dado
        # ausente por um borderô ausente.
        #
        # Onde a coluna aceita nulo, entra **nulo** — que é o valor que o próprio
        # legado já tem em 18.900 linhas de `nominal_tax_check`, e que diz "não
        # sei" em vez de afirmar um número. Onde ela é `null: false`, entra zero,
        # pelo mesmo motivo de `entrada_digitavel`.
        def sanear_nao_finitos!(atributos)
          atributos.each do |coluna, valor|
            next unless nao_finito?(valor)

            atributos[coluna] = aceita_nulo?(coluna) ? nil : BigDecimal(0)
          end
        end

        def aceita_nulo?(coluna)
          return true unless self.class.model_ready?(self.class.target_model)

          definicao = self.class.target_class.columns_hash[coluna.to_s]
          definicao.nil? || definicao.null
        end

        # ------------------------------------------------------------------
        # OPS-150 — o relatório. **É o entregável desta tarefa**, não a carga.
        # ------------------------------------------------------------------
        def anomalies(row)
          linhas = []
          linhas.concat(nan_anomalies(row))
          linhas.concat(django_etl_anomalies(row))
          linhas.concat(pre_company_anomalies(row))
          linhas
        end

        private

        # **D-10 / DEC-128.3 — as 32 linhas corrompidas, com origem e recálculo
        # lado a lado.**
        #
        # A decisão pede que os 32 saiam LISTADOS *"com o valor de origem e o
        # recalculado, lado a lado, para conferência"*. O valor listado é obtido
        # do **próprio `convert`**, e não de uma segunda conta escrita aqui: uma
        # lista que diverge do que foi gravado é pior do que não ter lista.
        #
        # `convert` só é chamado depois do retorno adiantado — as 28.099 linhas
        # íntegras não pagam por isto.
        def nan_anomalies(row)
          entradas = ENTRADAS_DIGITAVEIS.select { |c| nan_text?(row[c]) }
          derivados = DERIVED.select { |c| nan_text?(row[c]) }
          return [] if entradas.empty? && derivados.empty?

          gravado = convert(row)
          linhas = []
          linhas.concat(derivados_recalculados(row, gravado, derivados))
          linhas.concat(entradas_zeradas(row, entradas))
          linhas
        end

        # DEC-128.3 — recalcular NÃO inventa dado: restaura o que o próprio
        # cálculo deveria ter gravado, pelo mesmo motor da tela (contrato C2).
        def derivados_recalculados(row, gravado, derivados)
          return [] if derivados.empty?

          comparacao = derivados.map { |c| "#{c}: NaN -> #{formatar(gravado[c.to_sym])}" }.join(' · ')
          [{
            key: 'custom:receivable_entries_nan_derived',
            title: 'DEC-128.3 — derivados com `NaN` RECALCULADOS pelo motor (C2)',
            line: Values.anomaly_line(
              "D-10 — #{derivados.size} derivado(s) com `NaN` na origem, RECALCULADO(S) pelo " \
              "`Receivables::Calculator` a partir das entradas. Origem -> recalculado: #{comparacao}",
              self.class.source_table, row['id'], derivados.first, 'NaN'
            )
          }]
        end

        # Duas famílias, e a diferença importa:
        #
        # * **dedução** (`recompra`/`retencao`/`fomento`/`outros`) — `NaN` aqui é
        #   campo em branco da tela (`parseFloat("")`), e o servidor do legado já
        #   o tratava como zero. Cai na mesma decisão dos derivados;
        # * **raiz** (`valor_bruto`/`vlr_bruto_recusado`) — 1 linha em produção.
        #   Ali **não há derivado a restaurar**: o que se perdeu é a entrada de
        #   onde a conta sai. Chave de decisão PRÓPRIA, para que ninguém leia
        #   "32 recalculados" e ache que este caso também foi.
        def entradas_zeradas(row, entradas)
          entradas.map do |coluna|
            raiz = ENTRADAS_RAIZ.include?(coluna)
            {
              key: raiz ? 'custom:receivable_entries_nan_input' : 'custom:receivable_entries_nan_derived',
              title: if raiz
                       'D-10 — `NaN` na entrada RAIZ do borderô (o valor bruto)'
                     else
                       'DEC-128.3 — dedução com `NaN` na origem (campo em branco da tela)'
                     end,
              line: Values.anomaly_line(
                if raiz
                  'D-10 — `NaN` na entrada RAIZ: o valor bruto do borderô se perdeu e NÃO há derivado ' \
                    'que o restaure. Entra 0,00 (o `default` da coluna, que é `null: false`) e a linha ' \
                    'fica aqui, nomeada, para conferência humana antes do cutover.'
                else
                  'DEC-128.3 — dedução com `NaN`: campo em branco da tela do legado ' \
                    '(`parseFloat("")`). Entra 0,00 — que é o que o próprio servidor do legado fazia ' \
                    '(`recompra.blank? ? 0`) — e os derivados saem do motor.'
                end,
                self.class.source_table, row['id'], coluna, 'NaN'
              )
            }
          end
        end

        def formatar(valor)
          case valor
          when nil then 'nulo'
          when BigDecimal then valor.to_s('F')
          else valor.to_s
          end
        end

        # OPS-150 / Q-B19 — o ETL Django→Rails de 2021 forçava `user_id = 1` e
        # `company_id = 1` nos borderôs de 2016-2021 (BE-452 (a)): quando
        # `carriers` e `receivable_entries` eram gravados, `users` ainda não
        # existia e não havia a quem apontar. **Esses registros estão em produção
        # com autoria errada por construção.**
        #
        # A decisão de reatribuir autor/empresa é **Q-B19, em aberto**. O
        # relatório é o entregável; a reatribuição não é feita aqui.
        def django_etl_anomalies(row)
          return [] if row['legacy_id'].to_s.strip.empty?
          return [] unless row['user_id'].to_s == '1' || row['company_id'].to_s == '1'

          [Values.anomaly_line(
            "Q-B19 — registro do importador Django (legacy_id=#{row['legacy_id']}) com " \
            "user_id=#{row['user_id']} / company_id=#{row['company_id']} forçados pelo ETL de 2021. " \
            'Reatribuir autor/empresa é decisão PENDENTE do usuário.',
            self.class.source_table, row['id'], 'user_id/company_id', row['user_id']
          )]
        end

        # DB-154 — `company_id` só passou a ser obrigatório em 22/03/2022
        # (`20220322123523`). Os borderôs anteriores receberam a empresa do
        # projeto por `ReceivableEntry.fix_entries_without_company`
        # (`../sfg/app/models/receivable_entry.rb:222-234`), que cria uma
        # "Empresa Padrão" quando o projeto não tem nenhuma.
        #
        # A correção **já rodou no legado** — em produção não há `company_id`
        # nulo. O relatório conta quantos borderôs anteriores a 03/2022 estão
        # apontando para a empresa que aquela rotina escolheu, que é o número
        # que a tarefa 5.4 pede.
        def pre_company_anomalies(row)
          return [] if row['date'].to_s >= '2022-03-22'

          [Values.anomaly_line(
            'DB-154 — borderô anterior a 22/03/2022: a empresa foi atribuída em bloco por ' \
            '`fix_entries_without_company`, não escolhida no lançamento.',
            self.class.source_table, row['id'], 'company_id', row['company_id']
          )]
        end

        def nan_text?(value)
          %w[NaN Infinity -Infinity].include?(value.to_s.strip)
        end
      end
    end
  end
end
