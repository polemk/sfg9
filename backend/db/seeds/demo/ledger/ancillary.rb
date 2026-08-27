# frozen_string_literal: true

module Demo
  class Ledger
    # Renegociações, garantias e indicadores.
    #
    # Os indicadores são o ponto onde a cadeia **fecha visivelmente**: o valor do
    # gráfico não é um número novo, é uma **agregação da mesma lista** que a tela
    # de borderôs mostra. Faturamento subindo com volume descendo, sem motivo, é o
    # tipo de coisa que um analista percebe em dois segundos.
    module Ancillary
      # Fornecedores fictícios das renegociações. Nome de fornecedor é o que
      # aparece na coluna denormalizada `provider_name`.
      #
      # **São 16 e não 8 por uma razão de esquema, não de estética:** a
      # `integration_key` da renegociação é derivada do nome do fornecedor e é
      # **única por projeto** (S9). Dois fornecedores repetidos no mesmo cliente
      # colidem — no legado colidiam em silêncio. Como o cliente com mais
      # renegociações tem 13, a lista precisa de pelo menos 13 nomes para que
      # cada renegociação tenha o seu fornecedor.
      PROVIDERS = [
        'Metalpar Insumos Industriais Ltda',
        'Rodoviário Cristal Transportes Ltda',
        'Embalagens Novo Horizonte Ltda',
        'Energia e Utilidades Vale Verde S.A.',
        'Aços Continental Distribuidora Ltda',
        'Serviços Gerais Boa Vista Ltda',
        'Química Interlagos Comércio Ltda',
        'Manutenção Industrial Cedro Ltda',
        'Papel e Celulose Ribeirão Ltda',
        'Transportadora Piraquara Ltda',
        'Ferramentaria São Bento Ltda',
        'Componentes Elétricos Anhanguera Ltda',
        'Locação de Equipamentos Guaíba Ltda',
        'Fundição Morro Alto Ltda',
        'Tintas e Solventes Araucária Ltda',
        'Logística Portal do Sul Ltda',
        # --- As oito abaixo existem SÓ para dar FOLGA (ver PROVIDER_SLACK) ---
        # Nenhuma renegociação do razão as escolhe: o `provider_name` da
        # renegociação `i` é `PROVIDERS[(i - 1) % tamanho]`, e o cliente com mais
        # renegociações tem 13. Acrescentá-las **no fim** é o que garante que
        # nenhum número do seed já existente se mova — a fatia [0..12], que é a
        # que as renegociações consomem, continua idêntica.
        'Usinagem Vale do Sinos Ltda',
        'Refrigeração Ponta Grossa Ltda',
        'Autopeças Brasil Central Ltda',
        'Plásticos Serra do Mar Ltda',
        'Vidros e Cristais Itapema Ltda',
        'Cabos e Condutores Timbó Ltda',
        'Insumos Agrícolas Formosa Ltda',
        'Higienização Industrial Nova Era Ltda'
      ].freeze

      # **Fornecedores de folga por cliente — o conserto de uma tela que dava
      # 422 na apresentação.**
      #
      # A `integration_key` da renegociação é derivada do nome do fornecedor e é
      # **única por projeto** (`Renegotiation`, S9). Enquanto o seed cadastrava
      # exatamente os fornecedores que as renegociações já usavam, a tela "Nova
      # renegociação" oferecia uma lista em que **todo** item já estava gasto: o
      # `select` do formulário lista os fornecedores ATIVOS do projeto, e
      # qualquer escolha colidia com a chave existente. Medido antes do
      # conserto: folga zero nos 12 projetos, e 422 nos três fornecedores
      # oferecidos.
      #
      # Não é defeito de tela — é falta de dado. O cadastro de fornecedores de
      # um cliente real tem mais nomes do que dívidas renegociadas; um seed em
      # que os dois conjuntos coincidem é que era irreal.
      PROVIDER_SLACK = 5

      # Os quatro tipos do domínio fechado de `renegotiations.kind` (CHECK
      # `renegotiations_kind_domain`, D-B9). Escrever qualquer outro texto aqui é
      # um 422 na cara do escritor — e é assim que se descobre que o razão estava
      # falando uma língua que a tabela não fala.
      RENEGOTIATION_KINDS = %w[Financeiro Operacional Tributario Trabalhista].freeze

      # Quantas renegociações por cliente. **Concentradas** nos clientes 3, 7 e 11
      # (`demo-seed-design.md` §6) — renegociação espalhada por igual não conta
      # história nenhuma.
      #
      # Mas o piso é **três**, e não zero: a tela de Renegociações existe desde
      # que a S9 entregou, e o projeto que a apresentação abre primeiro é o
      # cliente #1. Com o plano antigo, quem clicasse em "Renegociações" na
      # primeira tela via uma lista vazia — que é o oposto do que esta fatia
      # existe para evitar. Concentração é contar história; ausência total é
      # tela morta.
      RENEGOTIATION_BASELINE = 3

      RENEGOTIATION_PLAN = {
        'serra-azul-textil' => 12,
        'porto-belo-comercial' => 9,
        'fundicao-tres-rios' => 13
      }.freeze

      # Tipos de garantia semeados como **PROVISÓRIOS** (DEC-86). A tabela existe
      # no legado e **nenhum seed a popula**: o select sobe vazio até alguém
      # cadastrar à mão. Não há nada a migrar — o conteúdo é novo, é suposição, e
      # a lista definitiva é do cliente. Substituir é trocar estas linhas.
      GUARANTEE_TYPES = [
        'Aval', 'Nota Promissória', 'Penhor Mercantil', 'Alienação Fiduciária',
        'Cessão Fiduciária de Recebíveis', 'Fiança Bancária', 'Hipoteca',
        'Seguro Garantia'
      ].freeze

      GUARANTEE_PROVISIONAL_NOTE =
        'Tipo provisório do seed de demonstração (DEC-86) — a lista definitiva é do cliente.'

      # **`value_type` aqui é o tipo do NEGÓCIO, não o da coluna.** O `Indicator`
      # aceita um valor só — `"Dinheiro"` (Q-R32) —, e o escritor grava apenas
      # os indicadores em dinheiro por isso: lançar um índice de recusa de 12,4
      # com `value_type: "Dinheiro"` faria o gráfico da demo imprimir "R$ 12,40"
      # para um percentual, que é exatamente a tela que finge.
      #
      # ## O "aguardando a S10" estava ERRADO, e o dump desmentiu (27/08/2026)
      #
      # Este comentário dizia que os três de percentual e de prazo *"passam a
      # ser gravados no dia em que a S10 acrescentar os tipos"*, e o
      # `demo-seed-design.md` §14 repetia a mesma expectativa. **Não há esse
      # dia.** Medido no dump de 31/05/2025:
      #
      #     select value_type, count(*) from indicators group by 1;
      #      Dinheiro | 529
      #
      # **529 de 529.** Produção nunca teve outro tipo, e o `VALUE_TYPES` de um
      # elemento é o espelho disso (DEC-30), não uma fatia pela metade.
      # Acrescentar percentual e dias seria acrescentar recurso que o legado não
      # tem — o que o DEC-09 desliga.
      #
      # Os três ficam no razão como **desenho de negócio pronto**, para o dia em
      # que o cliente pedir; nenhum deles é lacuna do seed.
      #
      # Os cinco em dinheiro saem todos da MESMA agregação dos borderôs e das
      # operações do mês: é o que faz o gráfico e a lista mostrarem o mesmo
      # número.
      INDICATORS = [
        { key: 'volume_operado', title: 'Volume operado', value_type: 'currency' },
        { key: 'valor_recusado', title: 'Valor recusado', value_type: 'currency' },
        { key: 'custo_total_tarifas', title: 'Custo total de tarifas', value_type: 'currency' },
        { key: 'indice_recusa', title: 'Índice de recusa', value_type: 'percent' },
        { key: 'custo_efetivo_medio', title: 'Custo efetivo médio', value_type: 'percent' },
        { key: 'prazo_medio_ponderado', title: 'Prazo médio ponderado', value_type: 'days' },
        { key: 'ticket_medio', title: 'Ticket médio por título', value_type: 'currency' },
        { key: 'exposicao_total', title: 'Exposição total', value_type: 'currency' }
      ].freeze

      # **INDICADORES ESPECÍFICOS DE PROJETO — o espelho estava invertido.**
      #
      # Produção tem **527 indicadores de projeto e 2 globais**; o seed tinha
      # **5 globais e ZERO específico**. A consequência não era estética: a
      # coluna "Alcance" da tela de Indicadores dizia "Global" em todas as
      # linhas, o selo não demonstrava que existe diferença, e a tela
      # "Indicadores específicos" nunca era exercitada por dado nenhum.
      #
      # Os globais **continuam sendo a maioria aqui**, e de propósito: é o
      # catálogo compartilhado que permite comparar carteira contra carteira,
      # que é a tela que a gestora usa. O que faltava era o outro lado existir.
      #
      # Cada específico é uma **agregação da mesma lista de borderôs** que
      # produz os globais — não um número novo. É a regra da §7 do desenho: o
      # que o painel mostra tem de sair da lista que a tela ao lado exibe.
      #
      # `source` nomeia o recorte, e o recorte é do NEGÓCIO do cliente:
      #
      #  - `:fidc_volume` / `:factoring_volume` — quanto do volume passou por
      #    FIDC e quanto passou por factoring. É a pergunta do diretor financeiro
      #    de um grupo que está trocando de fonte de recurso, e o recorte sai do
      #    **Agente financeiro** do portador — a mesma coluna que a tela de
      #    Portadores mostra, nunca uma classificação inventada para o seed;
      #  - `:iof` — o custo de IOF isolado, que é tributo e não taxa negociada;
      #  - `:desagio` — o custo de deságio isolado, que é o que se negocia.
      PROJECT_INDICATORS = {
        'serra-azul-textil' => [
          { key: 'volume_operado_com_fidc', title: 'Volume operado com FIDC',
            source: :fidc_volume },
          { key: 'custo_de_iof', title: 'Custo de IOF', source: :iof }
        ],
        'alianca-metalurgica' => [
          { key: 'custo_de_desagio', title: 'Custo de deságio', source: :desagio }
        ],
        'nordeste-alimentos' => [
          { key: 'volume_operado_com_factoring', title: 'Volume operado com factoring',
            source: :factoring_volume }
        ]
      }.freeze

      # Praças de fornecedor. Cidades industriais de verdade, espalhadas por
      # cinco estados — fornecedor com endereço todo na mesma cidade denuncia
      # seed tão rápido quanto nome "Empresa 1".
      PROVIDER_CITIES = [
        %w[Joinville SC], %w[Campinas SP], %w[Contagem MG], %w[Cascavel PR],
        ['Caxias do Sul', 'RS'], %w[Sorocaba SP], %w[Anápolis GO], %w[Camaçari BA],
        ['São Bernardo do Campo', 'SP'], %w[Blumenau SC]
      ].freeze

      module_function

      # ------------------------------------------------------------------
      # Fornecedores — a contraparte da renegociação
      # ------------------------------------------------------------------
      # **Escopados por projeto (C1)**: o mesmo nome vira uma linha por cliente
      # que o usa. Não é duplicação — é como o cadastro funciona, e é o que
      # permite a chave de integração da renegociação (derivada do nome do
      # fornecedor) ser única dentro do projeto.
      #
      # Cliente **sem** renegociação também recebe fornecedor: a tela de
      # Fornecedores é do cadastro, e abrir o cadastro de um cliente e encontrar
      # a lista vazia não demonstra recurso nenhum.
      def providers(clients, renegotiations, rng)
        used = renegotiations.group_by { |r| r.client.slug }
                             .transform_values { |list| list.map(&:provider_name).uniq }

        clients.flat_map do |client|
          stream = rng.keyed(:providers, client.slug)
          names = used.fetch(client.slug, [])
          names |= stream.sample(PROVIDERS, stream.int(3, 6)) if names.length < 3
          # A folga: nomes que NENHUMA renegociação deste cliente usa, para que
          # "Nova renegociação" tenha o que criar. Entram **depois** dos nomes já
          # usados, de modo que as chaves `<slug>-FOR01..` dos fornecedores
          # existentes continuem apontando para os mesmos títulos.
          livres = PROVIDERS - names
          names += stream.sample(livres, [PROVIDER_SLACK, livres.length].min)

          names.each_with_index.map do |title, i|
            own = rng.keyed(:provider, client.slug, title)
            city, uf = PROVIDER_CITIES[own.int(0, PROVIDER_CITIES.length - 1)]

            Records::Provider.new(
              key: "#{client.slug}-FOR#{format('%02d', i + 1)}",
              client: client, title: title,
              cnpj: Support::Br.cnpj(own.int(10_000_000, 79_999_999), 1),
              city: city, uf: uf
            )
          end
        end
      end

      # ------------------------------------------------------------------
      # Renegociações
      # ------------------------------------------------------------------
      # **Os dois estados que só existem de propósito.** A tela de renegociação
      # pinta quatro estados (`Renegotiation::STATES`), e dois deles não
      # aparecem sozinhos numa carteira saudável:
      #
      #  - **"Sem parcela cadastrada"** — a dívida foi negociada e o cronograma
      #    ainda não foi lançado. É o estado em que a renegociação nasce;
      #  - **"Inconsistente"** — as parcelas lançadas **não cobrem** a dívida
      #    contratada. No legado este estado era inalcançável (D-45: a linha
      #    seguinte o sobrescrevia), e o filtro da tela não devolvia nada. A S9
      #    consertou; sem uma linha assim no banco, ninguém vê o conserto.
      #
      # Ficam no cliente #11, o que está em recuperação — é onde a história já
      # justifica cadastro em andamento.
      SHOWCASE_STATES = { 'fundicao-tres-rios' => { 12 => :inconsistent, 13 => :empty } }.freeze

      def renegotiations(clients, companies_by_client, base_date, rng)
        clients.flat_map do |client|
          count = RENEGOTIATION_PLAN.fetch(client.slug, RENEGOTIATION_BASELINE)
          companies = companies_by_client.fetch(client.slug)
          showcase = SHOWCASE_STATES.fetch(client.slug, {})

          (1..count).map do |i|
            stream = rng.keyed(:renegotiations, client.slug, i)
            build_renegotiation(client, companies[stream.int(0, companies.length - 1)],
                                i, base_date, stream, showcase: showcase[i])
          end
        end
      end

      def build_renegotiation(client, company, index, base_date, stream, showcase: nil)
        original = Support::Money.natural(client.base_volume * stream.tailed(0.02, 0.22), stream)
        # A dívida renegociada tem duas metades no cadastro: o que **já estava
        # vencido** (`original_value`) e o que ainda ia vencer
        # (`original_pending_value`). Deixar a primeira em zero é deixar um campo
        # da tela zerado em 34 de 34 renegociações — e é justamente o campo que
        # explica por que houve renegociação.
        overdue_share = Support::Money.natural(original * stream.float(0.10, 0.45), stream)
        additional = Support::Money.natural((original + overdue_share) * stream.float(0.02, 0.14),
                                            stream)
        total_debt = Support::Money.round2(original + overdue_share + additional)

        count = stream.pick([6, 8, 10, 12, 18, 24])
        start = base_date >> stream.int(-20, -3)
        first_due = Date.new(start.year, start.month, stream.int(5, 25))

        installments = case showcase
                       when :empty then []
                       # Cobre ~62% da dívida: parcelas de menos, que é o que
                       # "Inconsistente" quer dizer.
                       when :inconsistent
                         split_installments(Support::Money.round2(total_debt * 0.62), count,
                                            first_due, base_date, stream)
                       else split_installments(total_debt, count, first_due, base_date, stream)
                       end
        paid = installments.select(&:is_paid)
        overdue = installments.select(&:is_overdue)
        paid_value = Support::Money.round2(paid.sum(&:paid_value))

        provider_name = PROVIDERS[(index - 1) % PROVIDERS.length]

        Records::Renegotiation.new(
          key: "#{client.slug}-RN#{format('%03d', index)}",
          client: client, company: company,
          provider_name: provider_name,
          title: "Renegociação #{provider_name.split.first} " \
                 "#{format('%02d', index)}/#{first_due.year}",
          kind: stream.weighted('Financeiro' => 62, 'Operacional' => 18,
                                'Tributario' => 13, 'Trabalhista' => 7),
          state: state_for(installments, total_debt),
          # A negociação é fechada ANTES do primeiro vencimento — entre 45 e 10
          # dias antes. Data de negociação depois da primeira parcela é o tipo de
          # detalhe que quem trabalha com isto lê como erro de cadastro.
          renegotiation_date: (installments.first&.due_date || first_due) - stream.int(10, 45),
          # Taxa acordada da renegociação, em % ao mês. Entra no valor presente
          # (`current_value`) — faixa de dívida renegociada com fornecedor, não a
          # de crédito bancário.
          operation_interest_rate: (stream.float(0.8, 2.4) * 100).round / 100.0,
          # "Valor Original **Vencido**" — a parte que já estava em atraso quando
          # a dívida foi renegociada. `original_pending_value` é a "A Vencer".
          original_value: overdue_share,
          original_pending_value: original,
          additional_value: additional,
          total_debt: total_debt,
          paid_value: paid_value,
          # Piso em zero: o legado deixa `pending_main_value` negativo, mas
          # `remaining_value` é o que a tela mostra e nunca fica negativo.
          # **A vencer é a soma do que as parcelas devem**, não `total − pago`:
          # numa renegociação inconsistente as parcelas não cobrem a dívida, e o
          # "R$ A Pagar" da tela mostra o que está lançado. É a mesma conta do
          # `Renegotiations::Formulas.aggregate`.
          remaining_value: Support::Money.round2(installments.sum(&:pending_value)),
          paid_percent: installments_total(installments).zero? ? 0.0 :
                          ((paid_value / installments_total(installments)) * 10_000).round / 100.0,
          installments_count: installments.length,
          paid_installments: paid.length,
          overdue_installments: overdue.length,
          first_due_date: installments.first&.due_date,
          last_due_date: installments.last&.due_date,
          installments: installments
        )
      end

      def installments_total(installments)
        Support::Money.round2(installments.sum(&:main_value))
      end

      # As parcelas **somam o total** — a última absorve o resíduo do
      # arredondamento. Rodapé que não fecha por dois centavos é rodapé que não
      # fecha.
      def split_installments(total_debt, count, first_due, base_date, stream)
        base = Support::Money.round2(total_debt / count)
        accumulated = 0.0

        (1..count).map do |number|
          main = number == count ? Support::Money.round2(total_debt - accumulated) : base
          accumulated = Support::Money.round2(accumulated + main)
          due_date = first_due >> (number - 1)
          past = due_date < base_date
          # Parcela vencida no passado: paga na maioria das vezes; o que sobra é
          # a inadimplência que o semáforo mostra.
          is_paid = past && stream.chance(0.82)
          late = past && !is_paid
          interest = if late
                       0.0
                     else
                       (if is_paid && stream.chance(0.25)
                          Support::Money.round2(main * stream.float(0.01,
                                                                    0.04))
                        else
                          0.0
                        end)
                     end

          Records::RenegotiationInstallment.new(
            renegotiation: nil, number: number, due_date: due_date,
            main_value: main,
            total_value: Support::Money.round2(main + interest),
            paid_value: is_paid ? Support::Money.round2(main + interest) : 0.0,
            is_paid: is_paid, is_overdue: late,
            pending_value: is_paid ? 0.0 : main
          )
        end
      end

      # **Espelho de `Renegotiations::Formulas.state_for`**, na mesma ordem de
      # ramos. Quem grava o estado no banco é a S9 (o agregado é recalculado pelo
      # serviço dela, e é ele que manda); o razão o calcula para poder afirmar,
      # no spec, quais estados a demonstração vai ter na tela — que é a diferença
      # entre uma lista colorida e uma lista de um pill só.
      def state_for(installments, total_debt)
        return 'Sem parcela cadastrada' if installments.empty?
        return 'Liquidado' if installments.sum(&:pending_value) <= 0
        return 'Inconsistente' if installments_total(installments) < total_debt - 0.005

        'Pago'
      end

      # ------------------------------------------------------------------
      # Garantias
      # ------------------------------------------------------------------
      def guarantees(clients, controls, rng)
        by_client = controls.group_by { |c| c.client.slug }

        clients.flat_map do |client|
          stream = rng.keyed(:guarantees, client.slug)
          carriers = by_client.fetch(client.slug, []).map(&:carrier).uniq
          next [] if carriers.empty?

          # Nem todo projeto tem garantia — e é isso que faz a coluna significar
          # alguma coisa quando tem.
          count = stream.weighted(0 => 8, 1 => 10, 2 => 16, 3 => 20, 4 => 18, 5 => 16, 6 => 12)

          # Combinações **distintas** de (contraparte, tipo): a chave natural do
          # escritor é `(project_id, title)`, e o título é formado por esses dois.
          # Sortear com repetição criaria duas garantias com o mesmo título e a
          # segunda sobrescreveria a primeira em silêncio.
          pairs = stream.sample(carriers.product(GUARANTEE_TYPES), count)

          pairs.each_with_index.map do |(carrier, type), i|
            Records::Guarantee.new(
              key: "#{client.slug}-GAR#{format('%02d', i + 1)}",
              client: client, carrier: carrier, guarantee_type: type,
              title: "#{type} — #{carrier.title}",
              value: Support::Money.natural(client.base_volume * stream.tailed(0.05, 0.6), stream),
              observation: GUARANTEE_PROVISIONAL_NOTE
            )
          end
        end
      end

      # ------------------------------------------------------------------
      # Indicadores — a agregação que amarra o painel ao borderô
      # ------------------------------------------------------------------
      def indicator_entries(clients, months, borderos, operations)
        borderos_by = borderos.group_by { |b| [b.client.slug, b.month.offset] }
        ops_by_client = operations.group_by { |o| o.client.slug }

        clients.flat_map do |client|
          months.flat_map do |month|
            batch = borderos_by[[client.slug, month.offset]]
            next [] if batch.nil? || batch.empty?

            month_entries(client, month, batch, ops_by_client.fetch(client.slug, []))
          end
        end
      end

      def month_entries(client, month, batch, operations)
        gross = Support::Money.round2(batch.sum(&:valor_bruto))
        refused = Support::Money.round2(batch.sum(&:vlr_bruto_recusado))
        # **É esta linha que o painel mostra.** Mesma soma, mesmos borderôs.
        volume = Support::Money.round2(batch.sum(&:vlr_bruto_final))
        fees = Support::Money.round2(batch.sum(&:valor_total_tarifas))
        titles = batch.sum(&:qtd_final)
        weighted_term = batch.sum { |b| b.prz_med_pond_bco * b.vlr_bruto_final }

        values = {
          'volume_operado' => volume,
          'valor_recusado' => refused,
          'custo_total_tarifas' => fees,
          'indice_recusa' => gross.zero? ? 0.0 : ((refused / gross) * 10_000).round / 100.0,
          'custo_efetivo_medio' => volume.zero? ? 0.0 : ((fees / volume) * 10_000).round / 100.0,
          'prazo_medio_ponderado' => volume.zero? ? 0.0 : (weighted_term / volume).round(1),
          'ticket_medio' => titles.zero? ? 0.0 : Support::Money.round2(volume / titles),
          'exposicao_total' => exposure_at(operations, month)
        }

        globais = INDICATORS.map do |indicator|
          Records::IndicatorEntry.new(
            client: client, indicator_key: indicator[:key],
            indicator_title: indicator[:title], value_type: indicator[:value_type],
            year: month.year, month: month.month,
            value: values.fetch(indicator[:key]), project_specific: false
          )
        end

        globais + project_entries(client, month, batch)
      end

      # Os lançamentos dos indicadores **do projeto**. Mesma lista de borderôs,
      # outro recorte — ver `PROJECT_INDICATORS`.
      def project_entries(client, month, batch)
        PROJECT_INDICATORS.fetch(client.slug, []).map do |indicator|
          Records::IndicatorEntry.new(
            client: client, indicator_key: indicator[:key],
            indicator_title: indicator[:title], value_type: 'currency',
            year: month.year, month: month.month,
            value: project_indicator_value(indicator[:source], batch),
            project_specific: true
          )
        end
      end

      # O recorte sai de `financial_agent`, que é a coluna "Agente financeiro" da
      # tela de Portadores. Atributo que o usuário enxerga — quem abrir a lista
      # de portadores consegue refazer a conta na mão, que é a prova de que o
      # painel não inventou o número.
      def project_indicator_value(source, batch)
        case source
        when :fidc_volume then volume_by_agent(batch, 'FIDC')
        when :factoring_volume then volume_by_agent(batch, 'Factoring')
        when :iof then Support::Money.round2(batch.sum(&:tarifa_iof))
        when :desagio then Support::Money.round2(batch.sum(&:tarifa_desagio))
        end
      end

      def volume_by_agent(batch, agent)
        Support::Money.round2(
          batch.select { |b| b.carrier.financial_agent == agent }.sum(&:vlr_bruto_final)
        )
      end

      # Exposição no fim do mês: para cada operação, o saldo do **último movimento
      # até aquela data**, com o sinal invertido (DEC-01). Derivada dos mesmos
      # movimentos que a tela de operação lista.
      def exposure_at(operations, month)
        month_end = Date.new(month.year, month.month, -1)
        total = operations.sum do |operation|
          last = operation.movements.reverse.find { |m| m.date <= month_end }
          last.nil? ? 0.0 : [-last.balance, 0.0].max
        end
        Support::Money.round2(total)
      end
    end
  end
end
