# frozen_string_literal: true

module Demo
  class Ledger
    # A matriz de **limite e taxa** — `risk_controls`, chave
    # `(company, carrier, risk_operation_type)`.
    #
    # No ai9 o controle tem **um** `limite` e **uma** `taxa`, e a modalidade é uma
    # linha de `risk_operation_types` (S5 §2). As 8 colunas pré-2022
    # (`limite_auto_liquidaveis`, `taxa_fomento`…) sobrevivem na migration por
    # paridade, mas o seed as deixa **nulas**: escrever nas duas gerações de coluna
    # ao mesmo tempo é ensinar a base a ter duas verdades.
    module Controls
      # Ajuste da taxa por modalidade, em pontos percentuais sobre a faixa da
      # contraparte. Auto-liquidável é o papel mais seguro e o mais barato;
      # comissária embute serviço e custa mais.
      MODALITY_RATE_DELTA = {
        auto_liquidavel: -0.34,
        fomento: 0.0,
        comissaria: 0.27,
        intercompany: -0.16
      }.freeze

      # **O PLANO DE UTILIZAÇÃO DE LIMITE.**
      #
      # `demo-seed-design.md` §3, princípio 6 — "estados misturados". Limite
      # apertado é um estado, e ele não estava representado. Medido no
      # `sfg9_dev` antes desta passada: **os 96 limites ativos em 0–30%**, com
      # máximo de **16,0%**. A faixa inteira de 30% para cima estava vazia, e a
      # consequência não era só o cartão "Limites no teto" da tela inicial vir
      # zerado: um cartão que só sabe dizer zero **não distingue "não há limite
      # estourado" de "a conta está quebrada"**, e o gráfico de consumo de
      # limite da S15 sairia com todas as barras rasteiras.
      #
      # Os alvos são por **grupo** (cliente × portador × modalidade), porque é
      # assim que a tela de risco agrega — marcar um controle solto mostra a
      # média diluída pelas outras empresas do grupo (era o 53% onde o razão
      # dizia 92%). A ordem é `[tamanho, chave]`: **o grupo MENOR recebe o alvo
      # mais alto**, para que o estouro caia no menor número possível de
      # limites. Um estouro escolhido demonstra o recurso; uma base inteira
      # estourada é cenário.
      #
      # Os dois clientes são os maiores da carteira — 19 e 13 limites ativos —,
      # então a escala aparece sem que a base pareça um desastre.
      # **A distribuição foi refeita em 27/08/2026, e o motivo é de
      # apresentação, não de modelo.** Medido pelos serviços do próprio sistema
      # (`Risk::AggregateService.controls_at_ceiling_on` /
      # `controls_near_ceiling_on`): **10 dos 12 projetos** davam `0` e `0` nos
      # dois indicadores da DEC-116. Estava correto — a faixa alta fora
      # concentrada nos dois maiores clientes de propósito —, mas quem abrisse
      # qualquer outro projeto na apresentação veria zero de novo, e um cartão
      # que só sabe dizer zero não distingue "não há limite estourado" de "a
      # conta está quebrada".
      #
      # A carteira agora tem os **três** estados representados, e a proporção
      # continua sendo a de uma carteira saudável:
      #
      # | estado | clientes |
      # | --- | ---: |
      # | com limite **acima de 100%** (cartão "Limites no teto") | 3 |
      # | com limite entre **90% e 100%** (lista "prestes a estourar") | +6 |
      # | **sem nenhum** dos dois — a carteira folgada | 3 |
      #
      # Os três sem nada não são sobra: `agroinsumos-cerrado` e
      # `litoral-norte-servicos` são os dois menores da carteira e
      # `tecnologia-ribeirao` entrou há dois meses. São eles que dão à
      # apresentação o contraste — sem um cliente tranquilo, a base inteira
      # parece um desastre e o indicador deixa de significar alguma coisa.
      UTILIZATION_PLAN = {
        # Os dois do roteiro: estouro, zona de perigo e aperto graduado.
        'alianca-metalurgica' => [1.09, 0.96, 0.84, 0.76],
        'serra-azul-textil' => [1.04, 0.91, 0.78],
        # Um terceiro estouro, num cliente de porte médio — para o cartão
        # "Limites no teto" não ser propriedade exclusiva dos dois maiores.
        'nordeste-alimentos' => [1.02, 0.93, 0.79],
        # Zona de perigo: um grupo por cliente, em graus diferentes. 92% e 98%
        # têm urgências diferentes, e é isso que a lista da DEC-116 mostra.
        'vale-do-rio-componentes' => [0.94],
        'campo-largo-distribuidora' => [0.97],
        'quimica-paulista' => [0.92],
        'moveis-bento-goncalves' => [0.95],
        'porto-belo-comercial' => [0.93],
        'fundicao-tres-rios' => [0.98]
      }.freeze

      # Abaixo deste alvo o razão **não força nada**: a geração comum já entrega
      # a faixa folgada de 0–30%, que é o caso mais frequente e continua sendo a
      # maioria da base.
      FORCED_UTILIZATION_FLOOR = 0.72

      module_function

      def build(clients, companies_by_client, rng)
        stream = rng.for(:controls)
        controls = []

        clients.each do |client|
          carriers = client.carrier_keys.map { |key| Cast.carrier(key) }
          companies = companies_by_client.fetch(client.slug)
          shares = company_shares(companies.length)

          companies.each_with_index do |company, index|
            # A empresa operacional (a primeira) trabalha com todas as
            # contrapartes do grupo; as periféricas, com uma ou duas.
            company_carriers =
              if index.zero?
                carriers
              else
                stream.sample(carriers, [stream.int(1, 2), carriers.length].min)
              end

            company_carriers.each do |carrier|
              modalities = modalities_for(company, carrier, index, stream)
              modalities.each do |modality|
                controls << build_control(client, company, carrier, modality,
                                          shares[index], modalities.length, stream)
              end
            end
          end
        end

        assign_utilization_plan(controls)
        controls
      end

      # A empresa operacional concentra metade do volume; o resto se divide entre
      # as periféricas, em ordem decrescente. Grupo em que todas as empresas
      # operam o mesmo valor não existe.
      def company_shares(count)
        return [1.0] if count == 1

        rest = (2..count).map { |i| 1.0 / i }
        total = rest.sum
        [0.5] + rest.map { |r| 0.5 * r / total }
      end

      def modalities_for(_company, carrier, index, stream)
        primary = index.zero? ? :fomento : stream.pick(%i[fomento auto_liquidavel])
        list = [primary]
        # Factoring não opera intercompany; banco e FIDC sim.
        extra_pool = if carrier.key == :vertice
                       %i[auto_liquidavel
                          comissaria]
                     else
                       %i[auto_liquidavel intercompany comissaria]
                     end
        list << stream.pick(extra_pool - list) if stream.chance(0.32)
        list.uniq
      end

      def build_control(client, company, carrier, modality, share, modality_count, stream)
        # Limite dimensionado pelo volume do cliente, pelo apetite da contraparte e
        # pela fatia da empresa no grupo. Grupo grande com limite de R$ 12 mil, ou
        # empresa de fundo de quintal com R$ 97 mi, é o defeito do seed do legado.
        limite = client.base_volume * carrier.limit_factor * share / modality_count
        limite *= stream.jitter(0.18)

        min_rate, max_rate = carrier.rate_range
        taxa = stream.float(min_rate, max_rate) + MODALITY_RATE_DELTA.fetch(modality)

        Records::Control.new(
          key: "#{company.key}/#{carrier.key}/#{modality}",
          client: client,
          company: company,
          carrier: carrier,
          modality: modality,
          limite: Support::Money.natural(limite, stream),
          taxa: (taxa * 10_000).round / 10_000.0,
          target_utilization: stream.float(0.28, 0.71)
        )
      end

      # Os grupos sob pressão são escolhidos **deterministicamente**, nunca
      # sorteados: o roteiro da apresentação precisa saber de antemão onde
      # clicar, e um alvo que muda de lugar a cada execução é pior que nenhum.
      def assign_utilization_plan(controls)
        UTILIZATION_PLAN.each do |slug, targets|
          groups = groups_for(controls, slug)

          targets.each_with_index do |target, index|
            grupo = groups[index]
            next if grupo.nil?

            grupo.each { |control| control.target_utilization = target }
          end
        end
      end

      # Os grupos do cliente, do MENOR para o maior e com desempate estável pela
      # chave. É a ordem que decide quantos limites ficam estourados: o alvo
      # acima de 100% é o primeiro da lista, e cair num grupo de um único
      # controle é o caso ideal.
      def groups_for(controls, slug)
        controls.select { |c| c.client.slug == slug }
                .group_by { |c| [c.carrier.key.to_s, c.modality.to_s] }
                .sort_by { |(carrier, modality), list| [list.size, carrier, modality] }
                .map(&:last)
      end
    end
  end
end
