# frozen_string_literal: true

module Risk
  # S5 / BE-249, BE-250, BE-251, BE-231 — **os agregados de exposição**.
  #
  # ## Um serviço parametrizado pelo escopo, não duas cópias
  #
  # No legado os agregados existem **duas vezes**: em `Company`
  # (`../sfg/app/models/company.rb:35-66, 79-82, 114-195`) e em `Project`
  # (`../sfg/app/models/project.rb:449-640`). Aqui o `scope` é um `Company` **ou**
  # um `Project` e o código é um só.
  #
  #
  # **O que isso significa, com honestidade: nao ha oraculo.** Estes valores foram
  # conferidos contra o **fonte de 2022** — arquivo e linha citados em cada
  # cenario —, e nao contra comportamento observado. O golden trava a LEITURA do
  # codigo de 2022; ele nao prova que o numero esta certo, prova que nao mudamos o
  # que o legado fazia. A DEC-103b manda espelhar, e e isso que esta feito.
  #
  # **A marca serve de ponteiro:** no dia em que um numero sair estranho, ela diz
  # em segundos que a resposta esta no fonte de 2022, e nao numa base de producao
  # que nunca teve estes registros.
  #
  # O esquema tipado de risco **nunca subiu**: `change_risk_control_fields`,
  # `create_risk_operation_types`, `create_risk_operations` e
  # `create_risk_movements` estão entre as **24 migrations que nunca rodaram**
  # (`analise-dump-producao.md` §1). Não existe uma única operação, um único
  # movimento nem um único limite tipado no dump.
  #
  #
  #
  #
  # **O que é validado EM produção, e vai sem marca:** as 4 famílias de limite
  # (`auto_liquidavel`, `comissaria`, `fomento`, `intercompany`) e as taxas —
  # 600 registros reais, três anos de uso.
  #
  # ## ATENÇÃO — as duas cópias NÃO são idênticas, e o material da fatia diz que são
  #
  # O `design.md` da S5 afirma que "`company.rb` ≡ `project.rb` linha a linha".
  # **Isso está errado**, e foi conferido na fonte. `total_limits_on`,
  # `limite_*_on` e `perc_limite_utilizado_on` são de fato idênticos; mas
  # `risk_controls_info_on` **diverge em três pontos materiais**:
  #
  # | | `Company#risk_controls_info_on` | `Project#risk_controls_info_on` |
  # | - | - | - |
  # | granularidade da linha | **um limite** (`rc_info[:id] = rc.id`) | **um portador**, somando os limites dele naquele tipo (`rc_info[:id] = nil`) |
  # | `formatted_limite_liquidavel` / `_pre` | recebem o **utilizado** — é o **D-95 (a)** | recebem o próprio valor — **sem** o defeito |
  # | `perc_liq` / `perc_pre` do cabeçalho | recebem **valor monetário** — é o **D-95 (b)** | recebem o **percentual** |
  # | `taxa` da linha | `rc.taxa` | média **ponderada** `Σ(limite × taxa) / Σlimite` |
  #
  # Ou seja: os dois erros de rótulo do D-95 existem **só no caminho da empresa**
  # — que é o caminho que a tela usa quando há empresa selecionada. Com "Grupo
  # econômico" (sem empresa) o console cai no caminho do projeto e mostra os
  # rótulos certos. **DEC-01 manda replicar as duas**, e é o que este serviço faz:
  # o ramo é escolhido pela classe do escopo, exatamente como o controller legado
  # escolhia (`risk_controls_controller.rb:32-39`).
  #
  # Unificar os dois ramos "porque um deles está certo" mudaria número na tela
  # principal do produto sem ninguém ter decidido isso. Golden `L3` trava os dois.
  # ## Custo MEDIDO — antes e depois, no mesmo banco
  #
  # Medido no banco de dev em 26/08/2026, com o seed de demonstração:
  #
  # | escopo | limites | operações | movimentos | antes | depois |
  # | ------ | ------: | --------: | ---------: | ----: | -----: |
  # | projeto | 18 | 212 | 1.043 | 437 ms · **495 consultas** | 213 ms · **76 consultas** |
  # | projeto | 7 | 74 | 381 | 309 ms · 191 consultas | 125 ms · 50 consultas |
  # | empresa | 7 | 74 | 381 | 37 ms · 79 consultas | 50 ms · 25 consultas |
  #
  # **−85% de consultas no pior caso.** O custo deixou de crescer com
  # `operações × fórmulas` e passa a crescer com o número de **limites**.
  #
  # ### O que foi feito — e o que NÃO foi
  #
  # Três N+1 fechados, nenhum deles no somatório:
  #
  # 1. **o saldo por operação** virou uma consulta em lote por conjunto
  #    (`BalanceReader`, `DISTINCT ON`), em vez de uma por operação;
  # 2. **a lista de operações e a de limites por tipo** passaram pela memória de
  #    apuração (`ExposureCache`) — `total_limits_on` pedia a mesma lista três
  #    vezes por tipo;
  # 3. **portador, grupo, tipo e subtipos** vêm no `includes`, e o agrupamento
  #    por (portador, tipo) é feito em Ruby sobre uma materialização só, em vez
  #    de uma consulta por par dentro de dois laços.
  #
  # **A ordem da soma não foi tocada** (decisão B-07). O laço que acumula
  # continua percorrendo as operações na ordem em que o banco as devolve, uma a
  # uma — com float na cadeia, é a ordem que decide o centavo. Nada virou
  # `SUM()`.
  #
  # ### Como se sabe que nenhum número mudou
  #
  # Não por leitura de código: por comparação. O payload completo de
  # `summary_on` + `total_limits_on` + `available_for_entry_on` de **40 escopos**
  # (todos os projetos e empresas com limite no banco de demonstração, 357 KB de
  # JSON) foi capturado antes e depois de cada passo e conferido **byte a byte**
  # — `sha256` idêntico nas três iterações. Mais os goldens `L1`..`L4`.
  #
  class AggregateService
    # DEC-116 — o corte da lista "prestes a estourar". Mora aqui, e não dentro
    # do `class << self`, para ser `Risk::AggregateService::NEAR_CEILING_THRESHOLD`
    # de fora: declarada lá dentro, a constante fica na classe singleton e o
    # consumidor recebe `uninitialized constant` (foi o que aconteceu).
    NEAR_CEILING_THRESHOLD = 0.90

    class << self
      include ApiResponseHandler

      # ---------------------------------------------------------------------
      # Escopo
      # ---------------------------------------------------------------------
      # Os limites **ativos** do escopo. Todo agregado parte daqui — é o
      # `active_risk_controls` do legado, e é por ele que o limite desativado
      # some do console (decisão B-02, primeira metade).
      def active_controls(scope)
        base_controls(scope).active
      end

      # A mesma relação, com tudo o que as LINHAS leem já carregado: o portador
      # (e o grupo dele), o tipo e os **subtipos** — estes últimos porque
      # `subtype_ids_for` os consulta uma vez por fórmula por limite.
      #
      # É o N+1 que não tem nada a ver com a soma, e que a B-07 não protege:
      # carregar junto não muda nem conjunto nem ordem de nada.
      def active_controls_for_rows(scope)
        active_controls(scope).includes(carrier: :group, risk_operation_type: :subtypes)
      end

      def base_controls(scope)
        case scope
        when ::Company then RiskControl.where(company_id: scope.id)
        when ::Project then RiskControl.for_project(scope)
        else raise ArgumentError, "Escopo de agregação inválido: #{scope.class}"
        end
      end

      # ---------------------------------------------------------------------
      # BE-249 — agregados por tipo
      # ---------------------------------------------------------------------
      # Soma linha a linha, na ordem do banco (B-07).
      def limite_utilizado_on(scope, type, date = Date.current, cache: nil)
        cache ||= ExposureCache.new
        total = 0
        # A lista de limites do tipo vem da memória: `total_limits_on` pede a
        # mesma três vezes por tipo (via `perc_`, `disponivel_` e direto).
        cache.controls_of_type(scope, type) { active_controls_for_rows(scope).where(risk_operation_type_id: type.id).to_a }
             .each do |control|
          total += Calculator.limite_utilizado_on(control, date, cache: cache)
        end
        total
      end

      # **Ignora a data**, de propósito: é a soma da coluna `limite` dos limites
      # ativos do tipo. O parâmetro existe só para a assinatura bater com os
      # irmãos, como no legado (`company.rb:45-49`).
      def limite_total_on(scope, type, _date = Date.current, cache: nil)
        limites =
          if cache
            cache.controls_of_type(scope, type) { active_controls_for_rows(scope).where(risk_operation_type_id: type.id).to_a }
                 .map(&:limite)
          else
            active_controls(scope).where(risk_operation_type_id: type.id).pluck(:limite)
          end

        limites.sum
      end

      def limite_disponivel_on(scope, type, date = Date.current, cache: nil)
        cache ||= ExposureCache.new
        (limite_total_on(scope, type, date, cache: cache) - limite_utilizado_on(scope, type, date, cache: cache)).to_f
      end

      # **A divisão protegida.** `total = 0` com `utilizado > 0` devolve
      # `"100.00%"`; `total = 0` com `utilizado ≤ 0` devolve `"0.00%"`. É por
      # isso que limite zero continua sendo um cadastro válido — é ele que
      # mantém este ramo vivo.
      def perc_limite_utilizado_on(scope, type, date = Date.current, cache: nil)
        cache ||= ExposureCache.new
        total = limite_total_on(scope, type, date, cache: cache)
        utilizado = limite_utilizado_on(scope, type, date, cache: cache)

        perc =
          if total != 0
            (utilizado.to_f / total.to_f) * 100.00
          elsif utilizado.positive?
            100
          else
            0.00
          end

        Money.percent(perc)
      end

      # ---------------------------------------------------------------------
      # BE-251 — totais consolidados
      # ---------------------------------------------------------------------
      # **As quatro chaves `liq`, `perc_liq`, `pre` e `perc_pre` recebem TODAS a
      # mesma string** de `perc_limite_utilizado_on` (`company.rb:79-82`). Não é
      # engano do porte: é o que o legado devolve, e o único consumidor
      # (`BE-052`, o resumo da empresa) já lê assim. DEC-01 — replicado, com
      # golden travando as quatro.
      #
      # `blank_total_limits_on` do legado **não** é portado: ele não tem
      # chamador, e o caminho vazio aqui é o mesmo método com zero limites.
      # Fica `dropped` com evidência.
      def total_limits_on(scope, date = Date.current, cache: nil)
        cache ||= ExposureCache.new
        limits = RiskOperationType.active.order(title: :asc).map do |type|
          perc = perc_limite_utilizado_on(scope, type, date, cache: cache)
          total = limite_total_on(scope, type, date, cache: cache)
          disp = limite_disponivel_on(scope, type, date, cache: cache)
          util = limite_utilizado_on(scope, type, date, cache: cache)

          {
            id: type.id,
            title: type.title,
            total: total,
            disp: disp,
            util: util,
            perc_util: perc,
            # As quatro iguais — ver o comentário acima.
            liq: perc,
            perc_liq: perc,
            pre: perc,
            perc_pre: perc,
            formatted_total: Money.brl(total),
            formatted_disp: Money.brl(disp),
            formatted_util: Money.brl(util)
          }
        end

        {
          date: date.to_s,
          limits: limits,
          # `(!available_controls_for_date(date).blank?).to_i` — 0/1, como no legado.
          has_risk_controls: available_for_entry_on(scope, date).exists? ? 1 : 0
        }
      end

      # ---------------------------------------------------------------------
      # BE-252 — limites "livres" numa data
      # ---------------------------------------------------------------------
      # Limites **ativos** que não têm nenhuma operação vigente na data.
      #
      # **Consequência a preservar:** limite de tipo COM pré-faturamento nunca
      # aparece aqui, porque o par estático está sempre na janela (B-08 mantém o
      # mesmo efeito das sentinelas de ±2000 anos). É assim no legado, e é o
      # contrato que a S6 consome (OPS-238).
      def available_for_entry_on(scope, date = Date.current)
        ativos = active_controls(scope)
        ocupados = RiskOperation.where(risk_control_id: ativos.select(:id)).on_date(date)
                                .distinct.pluck(:risk_control_id)

        ativos.where.not(id: ocupados).order(title: :asc)
      end

      # ---------------------------------------------------------------------
      # BE-250 — o payload detalhado (por tipo → por linha)
      # ---------------------------------------------------------------------
      def controls_info_on(scope, date = Date.current, carrier_id = nil, cache: nil)
        cache ||= ExposureCache.new
        case scope
        when ::Company then company_controls_info_on(scope, date, carrier_id, cache)
        when ::Project then project_controls_info_on(scope, date, carrier_id, cache)
        else raise ArgumentError, "Escopo de agregação inválido: #{scope.class}"
        end
      end

      # ---------------------------------------------------------------------
      # BE-231 — o payload do console
      # ---------------------------------------------------------------------
      # Sem `company`, agrega o **projeto inteiro** (a opção "Grupo econômico" da
      # tela); com `company`, agrega a empresa. `is_single` é a presença de
      # `carrier`, e é ela que troca o layout.
      #
      # O escopo por projeto é aplicado no endpoint (`current_project!`); aqui a
      # empresa e o portador já chegam resolvidos **dentro** dele.
      def summary_on(project:, company: nil, carrier: nil, date: Date.current)
        scope = company || project
        # **UMA memória para a tela inteira.** Os dois payloads (`total_limits` e
        # `controls_info`) percorrem os mesmos limites e as mesmas operações; sem
        # compartilhá-la, cada um paga o próprio N+1.
        cache = ExposureCache.new

        {
          date: date.to_s,
          scope: company ? 'company' : 'project',
          company_id: company&.id,
          carrier_id: carrier&.id,
          is_single: carrier.present?,
          carrier_title: carrier&.title.to_s,
          total_limits: total_limits_on(scope, date, cache: cache),
          controls_info: controls_info_on(scope, date, carrier&.id, cache: cache)
        }
      end

      # ---------------------------------------------------------------------
      # S15 / NEW-002 — os agregados que o resumo da tela inicial LÊ
      # ---------------------------------------------------------------------
      # **Por que moram aqui e não no endpoint do dashboard.** O contrato C2 diz
      # que todo número tem UMA origem. Somar a exposição dentro do compositor do
      # dashboard criaria a segunda implementação da mesma fórmula — o D-09 —, e
      # no dia em que a regra de `limite_utilizado_on` mudasse, a tela inicial e
      # a tela de risco passariam a mostrar números diferentes sem ninguém
      # perceber. Os três métodos abaixo **não têm aritmética financeira nova**:
      # cada um percorre o que `total_limits_on` / `Calculator` já calculam.
      #
      # Dono: **S5** (esta fatia). Consumidor: S15.

      # A exposição do escopo numa data: a soma dos `util` que o console de risco
      # já mostra tipo a tipo. É literalmente a coluna "Lim. util" somada — e é
      # por isso que o cartão do dashboard e a tela de risco nunca divergem.
      def exposure_total_on(scope, date = Date.current, cache: nil)
        cache ||= ExposureCache.new
        total_limits_on(scope, date, cache: cache)[:limits].sum { |linha| linha[:util] }
      end

      # Quantos limites ATIVOS **atingiram o teto** na data — 100% ou mais.
      #
      # **DEC-116.** A regra era `disponivel < 0`, ou seja **estourado**. Isso
      # deixava de fora exatamente o caso que o rótulo descreve ao pé da letra: o
      # limite com consumo IGUAL ao teto, disponível zero. Passou a `<= 0`:
      # `100%` é teto atingido, `> 100%` é teto estourado, e os dois contam.
      #
      # Continua sendo `Calculator.limite_disponivel_on` — a mesma função do
      # semáforo da tela de risco (FE-238) —, para que o cartão e a cor da linha
      # nunca discordem. O que mudou foi a **pergunta**, não a conta.
      def controls_at_ceiling_on(scope, date = Date.current, cache: nil)
        cache ||= ExposureCache.new
        active_controls_for_rows(scope).order(title: :asc).count do |control|
          Calculator.limite_disponivel_on(control, date, cache: cache) <= 0
        end
      end

      # Os limites ATIVOS **na zona de perigo** na data — consumo >= 90% do teto.
      #
      # **DEC-116**, e é **lista, não contagem**, de propósito: 89% e 99% têm
      # urgências completamente diferentes, e um número único apagaria isso. É a
      # diferença entre saber que há risco e saber **onde**.
      #
      # **A faixa é FECHADA dos dois lados: `>= 90%` E `< 100%`.** Quem já
      # estourou **não está "prestes" a nada** — já aconteceu, e ele é contado
      # pelo cartão irmão. Com sobreposição os dois indicadores respondiam
      # parcialmente a mesma coisa e nenhum respondia inteiro: o leitor tinha de
      # reler cada porcentagem para separar o que ainda dá para evitar do que já
      # é fato consumado. Cada limite aparece em **exatamente um lugar**.
      #
      # O corte de cima é **`disponivel > 0`**, não `percent < 100`, e as duas
      # condições são aplicadas juntas de propósito: com teto zero a porcentagem
      # não existe, e o sinal do disponível é o único critério que sobra. Filtrar
      # só pela porcentagem deixaria esses limites escaparem pela borda que a
      # divisão por zero abre.
      #
      # **Teto zero fica FORA, e o motivo é este:** `utilizado / 0` não é 100% —
      # é indefinido. Deixar passar produziria `Infinity` no JSON e `NaN` na
      # tela, que é pior que a ausência da linha. Limite com teto zero é cadastro
      # válido (é o mesmo ramo que `perc_limite_utilizado_on` protege) e continua
      # aparecendo em todos os outros agregados.
      #
      # A porcentagem sai como **número**: quem formata é o front
      # (`Intl.NumberFormat('pt-BR')`), nunca o domínio — a mesma regra que tirou
      # a formatação monetária do backend (OPS-289).
      #
      # A forma espelha `volume_by_carrier_on`: mesmo escopo, mesma memória de
      # apuração, mesma ordenação explícita.
      def controls_near_ceiling_on(scope, date = Date.current, cache: nil, threshold: NEAR_CEILING_THRESHOLD)
        cache ||= ExposureCache.new

        linhas = active_controls_for_rows(scope).order(title: :asc).filter_map do |control|
          disponivel = Calculator.limite_disponivel_on(control, date, cache: cache)
          # Já atingiu ou passou do teto: é do cartão, não desta lista.
          next unless disponivel.positive?

          teto = control.limite.to_d
          next if teto <= 0

          utilizado = Calculator.limite_utilizado_on(control, date, cache: cache)
          fracao = utilizado.to_d / teto
          next if fracao < threshold.to_d

          {
            id: control.id,
            title: control.title.to_s,
            carrier_title: control.carrier&.title.to_s,
            operation_type_title: control.risk_operation_type&.title.to_s,
            used: utilizado,
            total: teto,
            available: disponivel,
            # Percentual como NÚMERO (98.7 e não "98.70%"). O front formata.
            percent: (fracao * 100).to_f
          }
        end

        # Do mais apertado para o menos. Empate desempata pelo título, para a
        # ordem não variar entre chamadas.
        linhas.sort_by { |linha| [-linha[:percent], linha[:title]] }
      end

      # Volume por PORTADOR na data: o limite utilizado de cada limite ativo,
      # acumulado pelo portador. Mesma função do agregado por tipo
      # (`limite_utilizado_on`), só que a chave do agrupamento é o portador.
      #
      # A ordem de acumulação segue `title: :asc`, a mesma do ramo empresa
      # (`company_controls_info_on`) — com float na cadeia, a ordem decide o
      # centavo (decisão B-07), então ela não pode ser acidental.
      #
      # Devolve uma lista ordenada por volume decrescente, no formato que o
      # gráfico de barras consome (`{ label:, value: }`). **Lista vazia** quer
      # dizer "não há limite ativo neste projeto" — que não é o mesmo que "todos
      # os portadores estão zerados", e é o front que distingue os dois.
      def volume_by_carrier_on(scope, date = Date.current, cache: nil)
        cache ||= ExposureCache.new
        por_portador = Hash.new(0)

        active_controls_for_rows(scope).order(title: :asc).each do |control|
          rotulo = control.carrier&.title.to_s
          rotulo = 'Sem portador' if rotulo.empty?
          por_portador[rotulo] += Calculator.limite_utilizado_on(control, date, cache: cache)
        end

        por_portador.sort_by { |rotulo, valor| [-valor, rotulo] }
                    .map { |rotulo, valor| { label: rotulo, value: valor } }
      end

      private

      # === Ramo EMPRESA — uma linha por limite, com os dois erros do D-95 =====
      # Réplica de `../sfg/app/models/company.rb:114-195`.
      def company_controls_info_on(company, date, carrier_id, cache)
        controls = active_controls_for_rows(company)
        controls = carrier_id.present? ? controls.where(carrier_id: carrier_id) : controls.order(title: :asc)

        # Materializa UMA vez e agrupa em Ruby. `group_by` preserva a ordem
        # relativa dentro de cada grupo, então o conjunto e a ordem da soma são
        # os mesmos de `controls.where(type)` — sem uma consulta por tipo.
        por_tipo = controls.to_a.group_by(&:risk_operation_type_id)

        RiskOperationType.active.order(title: :asc).filter_map do |type|
          do_tipo = por_tipo[type.id] || []
          next if do_tipo.empty?

          acumulado = Hash.new(0)
          linhas = do_tipo.map do |control|
            linha = company_row(control, type, date, cache)
            %i[limite_utilizado limite_liquidavel limite_pre limite_disponivel limite_total].each do |chave|
              acumulado[chave] += linha[:limits][chave]
            end
            linha
          end

          type_header(type, acumulado, linhas, monetary_percent_labels: true)
        end
      end

      def company_row(control, type, date, cache)
        utilizado = Calculator.limite_utilizado_on(control, date, cache: cache)
        liquidavel = Calculator.limite_liquidavel_on(control, date, cache: cache)
        pre = Calculator.limite_pre_on(control, date, cache: cache)
        disponivel = Calculator.limite_disponivel_on(control, date, cache: cache)
        total = control.limite

        perc_util = percent_of(utilizado, total)
        perc_liq = percent_of(liquidavel, total)
        perc_pre = percent_of(pre, total)

        {
          id: control.id,
          risk_title: control.carrier.title,
          risk_subtitle: control.carrier.group&.title.to_s,
          operation_type_title: type.title,
          has_pre: type.has_pre_faturamento?,
          limits: {
            limite_utilizado: utilizado,
            limite_liquidavel: liquidavel,
            limite_pre: pre,
            limite_disponivel: disponivel,
            limite_total: total,
            limite_utilizado_percent: perc_util,
            limite_liquidavel_percent: perc_liq,
            limite_pre_percent: perc_pre,
            formatted_limite_disponivel: Money.brl(disponivel),
            formatted_limite_total: Money.brl(total),
            formatted_limite_utilizado: "#{Money.brl(utilizado)} - #{Money.brl(perc_util)}%",
            # **D-95 (a), REPLICADO**: a parte monetária das colunas "Liquidável"
            # e "Pré-Faturamento" recebe o **utilizado**, não o próprio valor
            # (`company.rb:158,164`). Só o percentual é do bucket certo. QA não
            # deve abrir bug — DEC-01.
            formatted_limite_liquidavel: "#{Money.brl(utilizado)} - #{Money.brl(perc_liq)}%",
            formatted_limite_pre: "#{Money.brl(utilizado)} - #{Money.brl(perc_pre)}%",
            taxa: control.taxa
          }
        }
      end

      # === Ramo PROJETO — uma linha por PORTADOR, sem os erros do D-95 ========
      # Réplica de `../sfg/app/models/project.rb:540-640`.
      def project_controls_info_on(project, date, carrier_id, cache)
        controls = active_controls_for_rows(project)
        controls = carrier_id.present? ? controls.where(carrier_id: carrier_id) : controls.order(title: :asc)
        carrier_ids = controls.pluck(:carrier_id).uniq

        # O legado monta `do_portador` a partir de `active_controls(project)` —
        # a relação **sem** o filtro de portador e **sem** ordem —, não a partir
        # da lista filtrada de cima. Preservado: o índice é do conjunto inteiro,
        # e é `carrier_ids` que carrega o recorte. Materializado uma vez e
        # indexado, em vez de uma consulta por (portador × tipo).
        por_portador_e_tipo = active_controls_for_rows(project)
                              .to_a.group_by { |c| [c.carrier_id, c.risk_operation_type_id] }

        RiskOperationType.active.order(title: :asc).filter_map do |type|
          acumulado = Hash.new(0)
          linhas = carrier_ids.filter_map do |cid|
            do_portador = por_portador_e_tipo[[cid, type.id]] || []
            next if do_portador.empty?

            linha = project_row(do_portador, cid, type, date, cache)
            %i[limite_utilizado limite_liquidavel limite_pre limite_disponivel limite_total].each do |chave|
              acumulado[chave] += linha[:limits][chave]
            end
            linha
          end

          next if linhas.empty?

          type_header(type, acumulado, linhas, monetary_percent_labels: false)
        end
      end

      def project_row(controls, carrier_id, type, date, cache)
        # O portador vem do próprio limite (já veio no `includes`), não de um
        # `Carrier.find` por linha — era uma consulta por portador por tipo.
        carrier = controls.first.carrier
        soma = Hash.new(0)
        valor_ponderado = 0

        controls.each do |control|
          soma[:limite_utilizado] += Calculator.limite_utilizado_on(control, date, cache: cache)
          soma[:limite_liquidavel] += Calculator.limite_liquidavel_on(control, date, cache: cache)
          soma[:limite_pre] += Calculator.limite_pre_on(control, date, cache: cache)
          soma[:limite_disponivel] += Calculator.limite_disponivel_on(control, date, cache: cache)
          soma[:limite_total] += control.limite
          valor_ponderado += control.limite * control.taxa
        end

        perc_util = percent_of(soma[:limite_utilizado], soma[:limite_total])
        perc_liq = percent_of(soma[:limite_liquidavel], soma[:limite_total])
        perc_pre = percent_of(soma[:limite_pre], soma[:limite_total])

        {
          # `nil` de propósito: a linha é de um PORTADOR, não de um limite —
          # pode agregar mais de um. `carrier_id` é o que a tela usa para
          # avisar quando isso acontece (FE-236).
          id: nil,
          carrier_id: carrier_id,
          controls_count: controls.size,
          risk_title: carrier.title,
          risk_subtitle: carrier.group&.title.to_s,
          operation_type_title: type.title,
          has_pre: type.has_pre_faturamento?,
          limits: {
            limite_utilizado: soma[:limite_utilizado],
            limite_liquidavel: soma[:limite_liquidavel],
            limite_pre: soma[:limite_pre],
            limite_disponivel: soma[:limite_disponivel],
            limite_total: soma[:limite_total],
            limite_utilizado_percent: perc_util,
            limite_liquidavel_percent: perc_liq,
            limite_pre_percent: perc_pre,
            formatted_limite_disponivel: Money.brl(soma[:limite_disponivel]),
            formatted_limite_total: Money.brl(soma[:limite_total]),
            formatted_limite_utilizado: "#{Money.brl(soma[:limite_utilizado])} - #{Money.brl(perc_util)}%",
            # Sem o D-95 (a): aqui cada rótulo recebe o próprio valor
            # (`project.rb:602-603`).
            formatted_limite_liquidavel: "#{Money.brl(soma[:limite_liquidavel])} - #{Money.brl(perc_liq)}%",
            formatted_limite_pre: "#{Money.brl(soma[:limite_pre])} - #{Money.brl(perc_pre)}%",
            # Média PONDERADA pelo limite (`project.rb:605`), não `rc.taxa`.
            taxa: soma[:limite_total] == 0 ? 0 : (valor_ponderado.to_f / soma[:limite_total].to_f)
          }
        }
      end

      # O cabeçalho do tipo. `monetary_percent_labels` é o D-95 (b): no ramo da
      # empresa, `perc_liq`/`perc_pre` recebem **valor monetário** formatado
      # (`company.rb:183,185`) e a view acrescenta "%"; no ramo do projeto
      # recebem o percentual (`project.rb:626,629`).
      def type_header(type, acumulado, linhas, monetary_percent_labels:)
        perc_util = percent_of(acumulado[:limite_utilizado], acumulado[:limite_total])
        perc_liq = percent_of(acumulado[:limite_liquidavel], acumulado[:limite_total])
        perc_pre = percent_of(acumulado[:limite_pre], acumulado[:limite_total])

        {
          id: type.id,
          title: type.title,
          has_pre: type.has_pre_faturamento?,
          util: acumulado[:limite_utilizado],
          disp: acumulado[:limite_disponivel],
          total: acumulado[:limite_total],
          liq: acumulado[:limite_liquidavel],
          pre: acumulado[:limite_pre],
          limite_utilizado_percent: perc_util,
          limite_liquidavel_percent: perc_liq,
          limite_pre_percent: perc_pre,
          perc_util: Money.brl(perc_util),
          perc_liq: monetary_percent_labels ? Money.brl(acumulado[:limite_liquidavel]) : Money.brl(perc_liq),
          perc_pre: monetary_percent_labels ? Money.brl(acumulado[:limite_pre]) : Money.brl(perc_pre),
          formatted_util: Money.brl(acumulado[:limite_utilizado]),
          formatted_disp: Money.brl(acumulado[:limite_disponivel]),
          formatted_total: Money.brl(acumulado[:limite_total]),
          formatted_liq: Money.brl(acumulado[:limite_liquidavel]),
          formatted_pre: Money.brl(acumulado[:limite_pre]),
          rcs: linhas
        }
      end

      # `total == 0 ? 100 : 100*(valor/total)` — a guarda do legado, que devolve
      # **100** quando não há teto. Aparece 12 vezes lá; aqui, uma.
      def percent_of(valor, total)
        return 100 if total.to_f.zero?

        100 * (valor.to_f / total.to_f)
      end
    end
  end
end
