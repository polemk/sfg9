# frozen_string_literal: true

module Dashboard
  # S15 / **NEW-002** — o resumo da tela inicial do console.
  #
  # ## Feature NOVA, não paridade
  #
  # Nada disto existe no legado: o `dash` dele é uma tela vazia com uma aba
  # "GERAL" (`dash/_body.js.erb:8-22`), e não há model, view SQL nem job que
  # alimente indicador de painel (`DB-399`, registrado como `dropped`). O QA do
  # Phase 4 **não deve procurar esta tela na origem**. Existe por decisão do
  # usuário (DEC-21).
  #
  # ## A regra que segura a fatia inteira: aqui não nasce número
  #
  # Este serviço é um **compositor**. Ele chama os serviços de domínio que já
  # calculam cada valor para a tela de detalhe correspondente e monta um payload
  # — **não existe agregação financeira própria**. Um `SUM(valor_bruto)` escrito
  # aqui daria ao sistema dois números para "total operado", e no dia em que a
  # regra mudasse num lado só, o usuário passaria a ver duas verdades sem que
  # ninguém percebesse. É o defeito **D-09**, e o contrato **C2** existe para
  # impedi-lo.
  #
  # | Cartão | Quem calcula | Fatia dona |
  # | ------ | ------------ | ---------- |
  # | Total operado | `Receivables::SearchService.totals` | S6 |
  # | Exposição | `Risk::AggregateService.exposure_total_on` | S5 |
  # | Limites no teto | `Risk::AggregateService.controls_at_ceiling_on` | S5 |
  # | Renegociações em atraso | `Renegotiations::AggregateService.overdue_renegotiations_count` | S9/S13 |
  # | Série do total operado | `Receivables::SearchService.monthly_totals` | S6 |
  #
  # ## Ausência não é zero (D-117)
  #
  # Cada cartão devolve `value: nil` quando **não há do que falar** — nenhum
  # borderô na janela, nenhum limite ativo, nenhuma renegociação no projeto — e
  # devolve o número quando há, **inclusive quando ele é zero**. `R$ 0,00` afirma
  # que se operou zero; "sem lançamentos no período" diz que não se operou. Num
  # sistema de crédito são informações diferentes, e a tela não pode confundi-las.
  #
  # ## Permissão: o cartão SOME, não vem zerado
  #
  # Cada cartão é montado só se a matriz DEC-18 der `read` no recurso dele ao
  # papel do solicitante. Um cartão zerado por falta de permissão seria uma
  # afirmação falsa sobre o dado — e, pior, indistinguível de "não há nada".
  #
  # ## Escopo
  #
  # O projeto chega **resolvido** (`current_project!`, contrato C1). Este serviço
  # nunca lê `project_id` de parâmetro: um agregado sem escopo vaza o número sem
  # mostrar a linha, que é a lição do **D-110**.
  class SummaryService
    # Quantos meses a série do total operado cobre, contando o mês da data de
    # referência. 12 é o que cabe legível num cartão de dashboard sem rótulo
    # sobreposto — medido renderizando, não estimado.
    DEFAULT_MONTHS = 12

    Card = Struct.new(:key, :label, :hint, :value, :format, :href, keyword_init: true) do
      def to_h
        { key: key, label: label, hint: hint, value: value, format: format, href: href }
      end
    end

    class << self
      # `date` é a data de apuração dos números pontuais (exposição, limites no
      # teto, renegociações em atraso). A janela do total operado e da série
      # termina no mês desta data e recua `months` meses.
      def call(project:, user:, date: Date.current, months: DEFAULT_MONTHS)
        date = date.to_date
        janela = window_for(date, months)

        new(project: project, user: user, date: date, window: janela).payload
      end

      def window_for(date, months)
        fim = date.end_of_month
        inicio = (date.beginning_of_month - (months.to_i - 1).months).beginning_of_month
        { from: inicio, to: fim }
      end
    end

    def initialize(project:, user:, date:, window:)
      @project = project
      @user = user
      @date = date
      @window = window
    end

    def payload
      {
        date: @date.to_s,
        # O NOME do projeto, para o cabeçalho poder dizer de quem é o número que
        # está na tela. Não é um número — é o escopo, e uma tela de resumo sem o
        # escopo escrito obriga a pessoa a conferir o seletor da barra lateral
        # para saber o que está lendo.
        project: { id: project.id, name: project.name },
        period: { from: @window[:from].to_s, to: @window[:to].to_s },
        # Só os cartões que este papel pode ver. A lista pode vir com menos de
        # quatro itens — e vir vazia é um estado legítimo, não um erro.
        cards: cards.compact.map(&:to_h),
        series: series,
        # Responde uma pergunta que os quatro números não respondem, e **não traz
        # número novo**: é uma re-serialização do que `total_limits_on` já
        # devolve para a tabela do console de risco.
        #
        # **A composição do borderô NÃO entra aqui, e o motivo importa:** medido
        # no seed, `líquido + tarifas` dá 9.255.605,12 contra um bruto de
        # 9.286.435,25 — sobram 30.830,13 de deduções que `valor_total_tarifas`
        # não cobre. Uma barra empilhada com essas três parcelas afirmaria uma
        # identidade que o dado não sustenta. Nomear o resto exigiria uma
        # decisão de domínio que não é desta fatia.
        limits: limits_by_type,
        near_ceiling: near_ceiling,
        overdue_renegotiations: overdue_renegotiations
      }
    end

    private

    attr_reader :project, :user, :date, :window

    def cards
      [total_operado_card, exposicao_card, limites_no_teto_card, renegociacoes_card]
    end

    # --- Cartão 1 — total operado (S6) -----------------------------------
    def total_operado_card
      return nil unless allow?('receivables')

      totais = receivables_totals
      Card.new(
        key: 'total_operado',
        label: 'Total operado',
        hint: periodo_legivel,
        # `count.zero?` é a ausência: nenhum borderô na janela. Com borderô, o
        # valor vai como está — inclusive zero, e inclusive negativo (DEC-01).
        value: totais[:count].to_i.zero? ? nil : totais[:valor_bruto],
        format: 'currency',
        href: '/receivables'
      )
    end

    # --- Cartão 2 — exposição (S5) ---------------------------------------
    def exposicao_card
      return nil unless allow?('risk')

      Card.new(
        key: 'exposicao',
        label: 'Exposição',
        hint: "em #{date.strftime('%d/%m/%Y')}",
        value: limites_ativos? ? ::Risk::AggregateService.exposure_total_on(project, date, cache: exposure_cache) : nil,
        format: 'currency',
        href: '/risk'
      )
    end

    # --- Cartão 3 — limites no teto (S5) ---------------------------------
    def limites_no_teto_card
      return nil unless allow?('risk_controls')

      Card.new(
        key: 'limites_no_teto',
        label: 'Limites no teto',
        # "disponível negativo" descrevia a REGRA, e no badge do cartão isso
        # lia como um estado ("este limite está negativo"). O badge carrega o
        # contexto do número, que é a data de apuração — igual aos irmãos.
        hint: "em #{date.strftime('%d/%m/%Y')}",
        value: limites_ativos? ? ::Risk::AggregateService.controls_at_ceiling_on(project, date, cache: exposure_cache) : nil,
        format: 'integer',
        href: '/risk-controls'
      )
    end

    # --- Cartão 4 — renegociações em atraso (S9/S13) ---------------------
    def renegociacoes_card
      return nil unless allow?('renegotiations')

      escopo = ::Renegotiation.for_project(project)
      Card.new(
        key: 'renegociacoes_em_atraso',
        label: 'Renegociações em atraso',
        hint: "em #{date.strftime('%d/%m/%Y')}",
        value: escopo.exists? ? ::Renegotiations::AggregateService.overdue_renegotiations_count(escopo, today: date) : nil,
        format: 'integer',
        href: '/renegotiations'
      )
    end

    # --- A série do total operado (S6) -----------------------------------
    #
    # Só sai quando o solicitante pode ver recebíveis — pelo mesmo motivo do
    # cartão: um gráfico zerado por falta de permissão mente sobre o dado.
    def series
      return nil unless allow?('receivables')

      linhas = ::Receivables::SearchService.monthly_totals(project, from: window[:from], to: window[:to])
      # `empty?` só acontece com janela inválida; janela válida e sem borderô
      # devolve os meses com zero, que é um fato apurado (ver `monthly_totals`).
      return { labels: [], values: [], has_data: false } if linhas.empty?

      {
        labels: linhas.map { |linha| linha[:month].strftime('%m/%Y') },
        values: linhas.map { |linha| linha[:value] },
        # Distingue "a janela inteira está zerada" de "há movimento". O front usa
        # isto para mostrar o estado vazio em vez de uma linha rente ao eixo,
        # que parece defeito de renderização.
        has_data: linhas.any? { |linha| linha[:value].to_d.nonzero? }
      }
    end

    # --- "Algum tipo de limite está perto do teto?" (S5) -------------------
    #
    # A pergunta que o gestor faz antes de aprovar a próxima operação. O
    # payload é `total_limits_on` — **o mesmo** que desenha a tabela do console
    # de risco —, reordenado do mais consumido para o menos.
    #
    # `percent_label` vem PRONTO do serviço (`Money.percent`) e é impresso como
    # chegou: é ele que carrega o comportamento que a DEC-01 manda preservar. O
    # cliente usa `used`/`total` só para o COMPRIMENTO da barra, que é geometria,
    # não número exibido.
    def limits_by_type
      return nil unless allow?('risk')
      return nil unless limites_ativos?

      linhas = ::Risk::AggregateService.total_limits_on(project, date, cache: exposure_cache)[:limits]

      # **Tipo sem NENHUM limite cadastrado não aparece** — é a mesma regra do
      # console de risco (`if !risk_controls_of_type.blank?`, FE-235). Sem ela o
      # painel mostrava "Comissária 0,00 de 0,00 · 0.00%" para tipos que o
      # projeto simplesmente não usa: quatro linhas onde há duas de informação.
      # Visto renderizando.
      #
      # O critério é **existir limite**, não "total maior que zero": limite com
      # teto zero é cadastro válido e continua aparecendo.
      tipos_usados = ::Risk::AggregateService.active_controls(project)
                                            .distinct.pluck(:risk_operation_type_id).to_set

      itens = linhas.select { |linha| tipos_usados.include?(linha[:id]) }.map do |linha|
        {
          label: linha[:title],
          used: linha[:util],
          total: linha[:total],
          available: linha[:disp],
          percent_label: linha[:perc_util],
          # O semáforo do FE-238, decidido **onde o número nasce**: disponível
          # negativo é limite estourado. Mandar o estado pronto impede que a
          # tela invente um segundo critério para a mesma cor.
          at_ceiling: linha[:disp].to_f.negative?
        }
      end

      {
        date: date.to_s,
        # Do mais consumido para o menos: é a ordem em que a pergunta é feita.
        # Empate desempata pelo título, para a ordem não variar entre chamadas.
        items: itens.sort_by { |i| [-(i[:total].to_f.zero? ? 0 : i[:used].to_f / i[:total].to_f), i[:label]] },
        has_data: itens.any?
      }
    end

    # --- "Quem está prestes a estourar?" (S5 / DEC-116) --------------------
    #
    # **Lista, não contagem.** O cartão "Limites no teto" diz QUANTOS já
    # atingiram 100%; esta lista diz QUEM ainda dá tempo de salvar (>= 90% e
    # < 100%) e em que grau. 89% e 99% têm urgências diferentes, e um número
    # único apagaria isso.
    #
    # **A faixa é fechada em cima**: quem já estourou não está "prestes" a nada.
    # Cada limite aparece em exatamente um dos dois indicadores — com
    # sobreposição, os dois respondiam parcialmente a mesma coisa e o leitor
    # tinha de reler cada porcentagem para separar o evitável do consumado.
    #
    # **Gate:** `risk_controls`, o mesmo do cartão irmão. Quem não alcança o
    # recurso não recebe nem um nem outro (a lista vem `nil`, não vazia — vazia
    # significa "nenhum limite apertado", que é uma resposta, e boa).
    def near_ceiling
      return nil unless allow?('risk_controls')
      return nil unless limites_ativos?

      linhas = ::Risk::AggregateService.controls_near_ceiling_on(project, date, cache: exposure_cache)

      {
        date: date.to_s,
        threshold: (::Risk::AggregateService::NEAR_CEILING_THRESHOLD * 100).to_i,
        items: linhas,
        # `false` aqui quer dizer **"nenhum limite acima do corte"**, que é uma
        # boa notícia — e não "não há informação". A tela precisa dos dois
        # estados separados para poder tranquilizar em vez de calar.
        has_data: linhas.any?
      }
    end

    # --- "Quais renegociações estão em atraso?" (S9/S13) -------------------
    #
    # O par da lista de limites, e é por isso que ela mora ao lado: o cartão
    # conta, a lista **nomeia**. Um gestor que vê "1 renegociação em atraso" não
    # sabe se são duas parcelas de um acordo pequeno ou doze de um grande — e é
    # essa diferença que decide para quem ele liga hoje.
    #
    # `MAX_LINHAS` existe porque isto é um painel, não a tela de renegociações:
    # o rodapé diz quantas ficaram de fora e o link leva à lista completa.
    # Truncar em silêncio seria mentir sobre o tamanho do problema.
    MAX_OVERDUE_ROWS = 6

    def overdue_renegotiations
      return nil unless allow?('renegotiations')

      escopo = ::Renegotiation.for_project(project)
      return { date: date.to_s, items: [], total: 0, has_data: false } unless escopo.exists?

      todas = ::Renegotiations::AggregateService.overdue_renegotiations_on(escopo, today: date)

      {
        date: date.to_s,
        items: todas.first(MAX_OVERDUE_ROWS),
        # O total **antes** do corte: é ele que o rodapé usa para dizer quantas
        # não couberam.
        total: todas.size,
        has_data: todas.any?
      }
    end

    # --- Apoio ------------------------------------------------------------

    # UMA memória de apuração para os dois cartões de risco: os dois percorrem
    # os mesmos limites e as mesmas operações. Sem compartilhá-la, cada um paga
    # o próprio N+1 (a mesma razão de `summary_on`).
    def exposure_cache
      @exposure_cache ||= ::Risk::ExposureCache.new
    end

    def limites_ativos?
      return @limites_ativos if defined?(@limites_ativos)

      @limites_ativos = ::Risk::AggregateService.active_controls(project).exists?
    end

    def receivables_totals
      @receivables_totals ||= ::Receivables::SearchService.totals(
        project, { date_from: window[:from], date_to: window[:to] }
      )
    end

    def periodo_legivel
      "#{window[:from].strftime('%m/%Y')} a #{window[:to].strftime('%m/%Y')}"
    end

    # A matriz DEC-18, e só ela. `authorize!` responde "este papel alcança o
    # recurso"; aqui a mesma pergunta é feita por cartão, porque o dashboard
    # cruza quatro recursos numa resposta só.
    def allow?(resource)
      ::Authorization::Matrix.allow?(user&.user_type&.name, resource, :read)
    end
  end
end
