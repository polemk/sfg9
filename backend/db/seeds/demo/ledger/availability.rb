# frozen_string_literal: true

module Demo
  class Ledger
    # **Disponibilidades** (S11) — a árvore de padrões e a grade de lançamentos.
    #
    # ## Por que esta parte do razão nasceu depois das outras
    #
    # A medição de 26/08/2026 encontrou disponibilidade em **2 dos 13 projetos**
    # do banco de demonstração, e as duas eram linhas soltas criadas à mão por
    # quem verificava a S11 — não havia escritor nenhum. Numa apresentação
    # conduzida por outra pessoa, um menu "Painel de Disponibilidade" que abre
    # vazio em dez clientes é o buraco mais visível do sistema.
    #
    # ## O que faz o painel ter o que mostrar
    #
    # O painel (`Availability::GridService.panel`) só é interessante quando três
    # coisas são verdadeiras ao mesmo tempo, e as três são decisões deste
    # arquivo:
    #
    # 1. **Duas ou mais empresas no projeto.** Com uma só, a linha de
    #    consolidação geral repete a da empresa e a tela mostra o mesmo número
    #    duas vezes. É por isso que `Cast::CLIENTS` subiu para duas empresas em
    #    onze dos doze clientes.
    # 2. **Datas diferentes dentro do mesmo mês.** É o que marca dias no
    #    calendário (FE-122) e o que faz o saldo acumulado variar entre um
    #    clique e outro.
    # 3. **Ao menos um padrão `is_adjusted`.** É o par "base × corrigido"
    #    (FE-134 / DEC-24): `original_value` é o que se digitou e `value` é o
    #    valor corrigido pela proporção de dias úteis já decorridos do mês. Sem
    #    um padrão assim, metade da tela de padrões não tem o que demonstrar.
    #
    # ## O razão só declara as FOLHAS
    #
    # Nó com filhos, padrão base e a linha de consolidação geral são
    # **derivados**: quem os materializa é o `after_save` de `AvailabilityEntry`,
    # que é exatamente o caminho por onde a tela grava. Declarar aqui o valor de
    # um nó pai seria inventar um segundo cálculo para o mesmo número — e é o
    # tipo de coisa que só aparece quando o total do painel não bate com a soma
    # das linhas na frente do cliente.
    module Availability
      # A árvore de padrões, em três níveis. É o **catálogo global**; cada
      # projeto recebe uma cópia derivada (`global_availability_template_id`),
      # que é como o sistema funciona de verdade.
      #
      # `scale` é a fração do volume mensal do cliente que aquela linha
      # representa, e existe só nas folhas — é ela que diz "isto é lançável".
      # `operation_type`: C = crédito, D = débito.
      CATALOG = [
        { path: '1', title: 'Disponibilidades', operation_type: 'C', deadline_type: 'CP',
          is_mandatory: true },
        { path: '1.1', title: 'Caixa e equivalentes', operation_type: 'C', deadline_type: 'CP',
          is_mandatory: true },
        { path: '1.1.1', title: 'Conta corrente', operation_type: 'C', deadline_type: 'CP',
          is_mandatory: true, scale: 0.045 },
        # **O par base × corrigido da FE-134.** Aplicação financeira rende ao
        # longo do mês, então o valor corrigido por dias úteis decorridos é o
        # que a linha significa. É o padrão que a demonstração abre para mostrar
        # os dois números lado a lado.
        { path: '1.1.2', title: 'Aplicações de liquidez imediata', operation_type: 'C',
          deadline_type: 'CP', is_adjusted: true, scale: 0.110 },
        { path: '1.2', title: 'Recebíveis a vencer', operation_type: 'C', deadline_type: 'CP' },
        { path: '1.2.1', title: 'Carteira própria', operation_type: 'C', deadline_type: 'CP',
          scale: 0.340 },
        # **Não cumulativo**: a carteira cedida já está no caixa como recurso
        # liberado; somá-la de novo contaria o mesmo dinheiro duas vezes. A
        # linha aparece na grade e contribui **zero** para o pai — é o único
        # jeito de a tela demonstrar o que `is_cumulative` faz.
        { path: '1.2.2', title: 'Carteira cedida', operation_type: 'C', deadline_type: 'CP',
          is_cumulative: false, scale: 0.220 },
        { path: '1.2.3', title: 'Cheques a compensar', operation_type: 'C', deadline_type: 'CP',
          scale: 0.060 },
        { path: '2', title: 'Compromissos', operation_type: 'D', deadline_type: 'CP' },
        { path: '2.1', title: 'Fornecedores', operation_type: 'D', deadline_type: 'CP',
          scale: 0.280 },
        { path: '2.2', title: 'Folha e encargos', operation_type: 'D', deadline_type: 'CP',
          scale: 0.090 },
        # Segundo padrão corrigido, e do lado do débito: tributo apurado corre
        # com o mês. Dois exemplos com naturezas opostas provam que a correção
        # não é enfeite de uma linha só.
        { path: '2.3', title: 'Tributos', operation_type: 'D', deadline_type: 'CP',
          is_adjusted: true, scale: 0.055 },
        { path: '2.4', title: 'Empréstimos e financiamentos (CP)', operation_type: 'D',
          deadline_type: 'CP', scale: 0.160 },
        # **O único padrão que NÃO vem do catálogo global.** Sem ele a coluna
        # "Marcadores" da tela de padrões fica monocromática — dezesseis linhas
        # dizendo "Global" e nenhuma dizendo "Específico" —, e o selo de escopo
        # deixa de demonstrar que existe diferença entre catálogo e customização
        # do projeto. É o cadastro que cada cliente faz por conta própria.
        { path: '2.5', title: 'Comissões de representantes', operation_type: 'D',
          deadline_type: 'CP', is_global: false, scale: 0.045 },
        { path: '3', title: 'Exigível de longo prazo', operation_type: 'D', deadline_type: 'LP' },
        { path: '3.1', title: 'Financiamentos', operation_type: 'D', deadline_type: 'LP',
          scale: 0.380 },
        { path: '3.2', title: 'Parcelamentos tributários', operation_type: 'D', deadline_type: 'LP',
          scale: 0.070 }
      ].freeze

      # Os dois clientes que a apresentação abre primeiro ganham **dois meses**
      # de grade, para que a navegação de mês do painel tenha para onde ir.
      SHOWCASE = %w[alianca-metalurgica serra-azul-textil].freeze

      # **A lacuna deliberada.** O cliente #12 entrou há dois meses: ele recebe a
      # árvore de padrões (a grade abre com as linhas certas) e **nenhum
      # lançamento**. É o estado vazio honesto do painel — e é o único projeto
      # em que ele aparece.
      WITHOUT_ENTRIES = %w[tecnologia-ribeirao].freeze

      # Dias-âncora dos lançamentos dentro do mês. Viram o dia útil igual ou
      # anterior, e o mês corrente nunca passa da data-base — lançamento com
      # data futura é o detalhe que denuncia o seed.
      #
      # **A própria data-base entra sempre** (`business_day_on_or_before`), e não
      # é detalhe: o painel abre com **hoje** selecionado. Sem lançamento em
      # hoje, a primeira coisa que quem apresenta vê é uma grade inteira de
      # `R$ 0,00` — com o calendário marcando pontos noutros dias e os cards de
      # saldo do mês cheios, que é pior do que vazio, porque parece defeito. Foi
      # exatamente o que a renderização de 26/08 mostrou.
      CURRENT_MONTH_ANCHORS = [4, 11, 18, 25].freeze
      PREVIOUS_MONTH_ANCHORS = [9, 23].freeze

      module_function

      # Só o que é catálogo. O padrão específico do projeto (`is_global: false`)
      # não tem linha global de origem — é isso que a coluna de escopo mostra.
      def global_templates
        @global_templates ||= templates.select(&:is_global)
      end

      def templates
        @templates ||= CATALOG.map do |node|
          parts = node[:path].split('.')
          Records::AvailabilityTemplate.new(
            key: node[:path],
            path: node[:path],
            parent_path: parts.length > 1 ? parts[0..-2].join('.') : nil,
            level: parts.length,
            position: parts.last.to_i,
            title: node[:title],
            operation_type: node[:operation_type],
            deadline_type: node[:deadline_type],
            is_adjusted: node.fetch(:is_adjusted, false),
            is_cumulative: node.fetch(:is_cumulative, true),
            is_mandatory: node.fetch(:is_mandatory, false),
            is_global: node.fetch(:is_global, true),
            scale: node[:scale]
          )
        end
      end

      def leaves
        @leaves ||= templates.select(&:leaf?)
      end

      # As datas de cada cliente. Mesmo mês, dias diferentes — é o que faz o
      # calendário marcar e o saldo acumulado variar.
      #
      # `limit` faz parte do **modo amostra** (ver `entries`).
      def dates_for(client, base_date, limit: nil)
        current = (CURRENT_MONTH_ANCHORS.map { |day| business_day_on_or_before(safe_date(base_date, day)) } +
                   [business_day_on_or_before(base_date)])
                  .select { |date| date <= base_date && date.month == base_date.month }
                  .uniq
                  .sort

        # **Começo de mês**: rodando o seed no dia 1º, o mês corrente tem uma data
        # só (a própria data-base). Aí o mês anterior entra **inteiro** — quatro
        # datas —, para que exista um mês com grade cheia de qualquer jeito. Nos
        # dois clientes da vitrine o mês anterior entra sempre, com duas datas,
        # para a navegação de mês do painel ter para onde ir.
        curto = current.length < 3
        previous_month = base_date << 1
        previous = (curto ? CURRENT_MONTH_ANCHORS : PREVIOUS_MONTH_ANCHORS)
                   .map { |day| business_day_on_or_before(safe_date(previous_month, day)) }
                   .uniq
                   .sort

        todas = if SHOWCASE.include?(client.slug) || curto
                  previous + current
                else
                  current
                end

        limit ? todas.last(limit) : todas
      end

      # Constrói a grade inteira. Devolve só as **folhas**.
      #
      # ## O modo amostra, e por que ele existe
      #
      # **Cada folha dispara a cascata de derivados do model** — pai, padrões
      # base seguintes e consolidação geral —, o que dá ~10 gravações por
      # célula. A grade cheia são 1.716 folhas, ou ~17 mil gravações: 21 s. O
      # spec do orquestrador grava o seed inteiro **uma vez por exemplo**, então
      # a grade cheia sozinha custaria mais de quatro minutos de suíte.
      #
      # Em `sample: true` a grade encolhe para **um** cliente e **uma** data. A
      # cascata continua sendo exercitada de ponta a ponta — seis empresas, os
      # três padrões base, consolidação geral, o nó não cumulativo e o par
      # corrigido —, com 4% do custo. Quem confere que a grade **real** tem três
      # ou mais datas no mesmo mês em onze projetos é o `coverage_spec.rb`, que
      # roda no razão e não paga nada por isso.
      #
      # O corte é agressivo porque o custo medido é agressivo: sob `SimpleCov`,
      # que instrumenta cada linha, a cascata é cinco vezes mais lenta do que
      # fora da suíte.
      def entries(clients, companies_by_client, base_date, rng, sample: false)
        dates_limit = sample ? 1 : nil

        clients.flat_map do |client|
          next [] if WITHOUT_ENTRIES.include?(client.slug)
          next [] if sample && client.slug != SHOWCASE.first

          companies = companies_by_client.fetch(client.slug, [])
          next [] if companies.empty?

          shares = Controls.company_shares(companies.length)
          dates = dates_for(client, base_date, limit: dates_limit)

          companies.each_with_index.flat_map do |company, index|
            dates.flat_map { |date| cells(client, company, shares[index], date, rng) }
          end
        end
      end

      def cells(client, company, share, date, rng)
        month = Records::Month.new(offset: 0, date: date, year: date.year, month: date.month,
                                   label: '', trend: 1.0, seasonality: 1.0, factor: 1.0)
        modifier = Timeline.client_modifier(client, month)

        leaves.map do |template|
          stream = rng.keyed(:availability, client.slug, company.key, template.path, date.to_s)
          value = cell_value(client, company, template, share, modifier, stream)

          Records::AvailabilityEntry.new(
            client: client, company: company, template_key: template.key,
            date: date, value: value
          )
        end
      end

      # O valor da célula. **Zero é um valor legítimo** e aparece de propósito em
      # duas linhas escolhidas: uma grade em que toda célula tem número não
      # demonstra o contador de lançamentos preenchidos nem o estado vazio de uma
      # linha, e é o tipo de uniformidade que denuncia dado gerado.
      def cell_value(client, company, template, share, modifier, stream)
        return 0.0 if empty_cell?(template, company)

        base = client.base_volume * share * template.scale * modifier
        Support::Money.natural(base * stream.jitter(0.22), stream)
      end

      def empty_cell?(template, company)
        return true if template.path == '1.2.3' && company.branch.even?
        return true if template.path == '3.2' && company.branch == 1

        false
      end

      # Sábado e domingo voltam para a sexta anterior. **Sem feriado**, pelo
      # mesmo motivo do `Sfg::BusinessDays` (D-03 / DEC-28): incluir calendário
      # aqui e não lá faria a data existir num critério e o multiplicador da
      # correção usar outro.
      def business_day_on_or_before(date)
        date -= 1 while [6, 7].include?(date.cwday)
        date
      end

      def safe_date(reference, day)
        last = Date.new(reference.year, reference.month, -1).day
        Date.new(reference.year, reference.month, [day, last].min)
      end
    end
  end
end
