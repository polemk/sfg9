# frozen_string_literal: true

module Demo
  class Ledger
    # O elenco fictício: contrapartes, clientes e empresas do grupo.
    #
    # **Dado autoral, escrito à mão.** Gerador genérico produz "Empresa 1" e cidade
    # dos EUA; o que dá credibilidade a uma demo de crédito é o nome que soa como
    # um cliente de verdade. São 12 clientes e 5 contrapartes — cabe escrever.
    module Cast
      # As 4 modalidades do Safegold. No ai9 elas são **linhas** de
      # `risk_operation_types`, não colunas de `risk_controls` (S5 §2).
      MODALITIES = {
        fomento: 'Fomento',
        comissaria: 'Comissária',
        intercompany: 'Intercompany',
        auto_liquidavel: 'Auto Liquidável'
      }.freeze

      # Modalidades que aceitam borderô. `intercompany` e `comissaria` operam por
      # lançamento manual — é a flag `allow_receivable_entries` do legado.
      RECEIVABLE_MODALITIES = %i[fomento auto_liquidavel].freeze

      # ---------------------------------------------------------------------
      # Contrapartes — `demo-seed-design.md` §5.1
      # ---------------------------------------------------------------------
      # **Fictícias de propósito.** O seed do legado usa CREFISA, que é instituição
      # real: numa demo comercial, carrier com nome de banco real sugere relação
      # que não existe. Os códigos bancários são **não atribuídos** — nunca
      # 001/237/341, que são BB/Bradesco/Itaú.
      #
      # Cada uma tem personalidade consistente: **quem cobra taxa menor concede
      # limite maior e recusa mais título**. É isso que faz a tela de comparação
      # entre contrapartes ter o que dizer, e é onde o cliente vai olhar.
      CARRIERS = [
        {
          key: :meridiano, title: 'Banco Meridiano S.A.', bank_code: '894',
          financial_agent: 'Securitizadora', group: 'Bancos de médio porte',
          net_worth: 312_478_209.44, senior_accounts: 1_842, subordinated_accounts: 341,
          subordinated_percent: 18.5, city: 'São Paulo', uf: 'SP',
          rate_range: [1.34, 1.68], limit_factor: 1.85, refusal_rate: 0.062,
          available_from: -23
        },
        {
          key: :aurora, title: 'FIDC Aurora Crédito', bank_code: '907',
          financial_agent: 'FIDC', group: 'Fundos multicedentes',
          net_worth: 148_732_915.08, senior_accounts: 964, subordinated_accounts: 272,
          subordinated_percent: 22.0, city: 'Rio de Janeiro', uf: 'RJ',
          rate_range: [2.18, 2.62], limit_factor: 1.20, refusal_rate: 0.041,
          # A entrada do Aurora no mês 9 é o degrau da série (§8). Antes dele o
          # cliente operava com 3 contrapartes e taxa média mais alta.
          available_from: -15
        },
        {
          key: :vertice, title: 'Vértice Fomento Mercantil Ltda', bank_code: '912',
          financial_agent: 'Factoring', group: 'Factorings independentes',
          net_worth: 41_206_884.71, senior_accounts: 0, subordinated_accounts: 0,
          subordinated_percent: nil, city: 'Campinas', uf: 'SP',
          rate_range: [2.70, 3.08], limit_factor: 0.55, refusal_rate: 0.018,
          available_from: -23
        },
        {
          key: :solaris, title: 'FIDC Solaris Recebíveis', bank_code: '923',
          financial_agent: 'FIDC', group: 'Fundos multicedentes',
          net_worth: 96_845_133.27, senior_accounts: 713, subordinated_accounts: 238,
          subordinated_percent: 25.0, city: 'Porto Alegre', uf: 'RS',
          rate_range: [2.26, 2.74], limit_factor: 1.05, refusal_rate: 0.049,
          available_from: -19
        },
        {
          key: :ipiranga, title: 'Cooperativa de Crédito Ipiranga', bank_code: '936',
          financial_agent: 'Cliente', group: 'Cooperativas',
          net_worth: 63_517_402.19, senior_accounts: 0, subordinated_accounts: 0,
          subordinated_percent: nil, city: 'Curitiba', uf: 'PR',
          rate_range: [1.72, 2.04], limit_factor: 0.78, refusal_rate: 0.033,
          available_from: -23
        }
      ].freeze

      # ---------------------------------------------------------------------
      # Clientes — `demo-seed-design.md` §5.2
      # ---------------------------------------------------------------------
      # A **cauda** é deliberada (§3, princípio 4): 2 grupos grandes, 4 médios, 4
      # pequenos, 1 em recuperação e 1 recém-entrante. Doze clientes do mesmo
      # tamanho é o que denuncia dado gerado.
      #
      # Os dois últimos existem por um motivo: o **#11** é o que dá conteúdo à tela
      # de renegociação e ao semáforo de risco; o **#12** prova que o sistema lida
      # com histórico curto sem quebrar gráfico.
      #
      # ## Por que `company_count` subiu (26/08/2026)
      #
      # O desenho original deixava quatro clientes com **uma** empresa e **uma**
      # contraparte. Medido na tela, isso não demonstra nada: sem duas empresas a
      # consolidação geral do painel de disponibilidade é idêntica à linha da
      # empresa única, e com um limite só a tela de Limites não tem carteira para
      # comparar. Onze dos doze passam a ter **duas ou mais** empresas e **duas ou
      # mais** contrapartes.
      #
      # O **#12 continua com uma empresa e uma contraparte de propósito**: é o
      # cliente que entrou há dois meses, e é ele que prova que as telas sobem com
      # histórico curto sem quebrar. Lacuna escolhida, e em minoria.
      CLIENTS = [
        {
          index: 1, slug: 'alianca-metalurgica', name: 'Grupo Aliança Metalúrgica',
          formal: 'Aliança Metalúrgica Participações S.A.', cnpj_root: 41_827_356,
          segment: 'Indústria', sub_segment: 'Metalurgia e siderurgia',
          city: 'Joinville', uf: 'SC', responsible: 'Ricardo Almeida',
          tier: :grande, company_count: 6,
          carrier_keys: %i[meridiano aurora vertice solaris ipiranga],
          base_volume: 12_400_000.0, closing_date_offset: -1_180, active_from: -23,
          story: :estavel
        },
        {
          index: 2, slug: 'nordeste-alimentos', name: 'Nordeste Alimentos',
          formal: 'Nordeste Alimentos Indústria e Comércio S.A.', cnpj_root: 18_450_912,
          segment: 'Indústria', sub_segment: 'Alimentos e bebidas',
          city: 'Recife', uf: 'PE', responsible: 'Patrícia Camargo',
          tier: :grande, company_count: 5,
          carrier_keys: %i[meridiano aurora solaris ipiranga],
          base_volume: 9_150_000.0, closing_date_offset: -965, active_from: -23,
          story: :estavel
        },
        {
          index: 3, slug: 'serra-azul-textil', name: 'Têxtil Serra Azul',
          formal: 'Têxtil Serra Azul Indústria Ltda', cnpj_root: 27_309_844,
          segment: 'Indústria', sub_segment: 'Têxtil e confecção',
          city: 'Blumenau', uf: 'SC', responsible: 'Eduardo Bittencourt',
          tier: :medio, company_count: 4, carrier_keys: %i[meridiano vertice solaris],
          base_volume: 4_180_000.0, closing_date_offset: -742, active_from: -23,
          story: :renegociador
        },
        {
          index: 4, slug: 'vale-do-rio-componentes', name: 'Componentes Vale do Rio',
          formal: 'Componentes Vale do Rio Indústria e Comércio Ltda', cnpj_root: 33_614_207,
          segment: 'Indústria', sub_segment: 'Autopeças',
          city: 'Betim', uf: 'MG', responsible: 'Juliana Rezende',
          tier: :medio, company_count: 3, carrier_keys: %i[meridiano aurora solaris],
          base_volume: 3_070_000.0, closing_date_offset: -688, active_from: -23,
          story: :estavel
        },
        {
          index: 5, slug: 'campo-largo-distribuidora', name: 'Distribuidora Campo Largo',
          formal: 'Campo Largo Distribuidora de Alimentos Ltda', cnpj_root: 22_781_530,
          segment: 'Comércio', sub_segment: 'Atacado e distribuição',
          city: 'Curitiba', uf: 'PR', responsible: 'Marcelo Tavares',
          tier: :medio, company_count: 3, carrier_keys: %i[ipiranga solaris vertice],
          base_volume: 2_640_000.0, closing_date_offset: -604, active_from: -23,
          story: :crescente
        },
        {
          index: 6, slug: 'quimica-paulista', name: 'Química Paulista Reunidas',
          formal: 'Química Paulista Reunidas S.A.', cnpj_root: 15_902_463,
          segment: 'Indústria', sub_segment: 'Químicos e plásticos',
          city: 'Diadema', uf: 'SP', responsible: 'Cristina Vasconcelos',
          tier: :medio, company_count: 3, carrier_keys: %i[meridiano vertice ipiranga],
          base_volume: 1_920_000.0, closing_date_offset: -541, active_from: -23,
          story: :estavel
        },
        {
          index: 7, slug: 'porto-belo-comercial', name: 'Comercial Porto Belo',
          formal: 'Comercial Porto Belo Importação e Exportação Ltda', cnpj_root: 39_128_675,
          segment: 'Comércio', sub_segment: 'Comércio exterior',
          city: 'Santos', uf: 'SP', responsible: 'André Sampaio',
          tier: :pequeno, company_count: 2, carrier_keys: %i[vertice ipiranga solaris],
          base_volume: 824_000.0, closing_date_offset: -498, active_from: -23,
          story: :renegociador
        },
        {
          index: 8, slug: 'agroinsumos-cerrado', name: 'Agroinsumos Cerrado',
          formal: 'Agroinsumos Cerrado Comércio de Fertilizantes Ltda', cnpj_root: 29_663_018,
          segment: 'Comércio', sub_segment: 'Insumos agrícolas',
          city: 'Rio Verde', uf: 'GO', responsible: 'Renata Queiroz',
          tier: :pequeno, company_count: 2, carrier_keys: %i[solaris vertice],
          base_volume: 641_000.0, closing_date_offset: -412, active_from: -23,
          story: :sazonal_forte
        },
        {
          index: 9, slug: 'moveis-bento-goncalves', name: 'Móveis Bento Gonçalves',
          formal: 'Móveis Bento Gonçalves Indústria Ltda', cnpj_root: 12_047_589,
          segment: 'Indústria', sub_segment: 'Móveis e madeira',
          city: 'Bento Gonçalves', uf: 'RS', responsible: 'Fernando Bastos',
          tier: :pequeno, company_count: 2, carrier_keys: %i[ipiranga vertice solaris],
          base_volume: 518_000.0, closing_date_offset: -376, active_from: -23,
          story: :estavel
        },
        {
          index: 10, slug: 'litoral-norte-servicos', name: 'Serviços Litoral Norte',
          formal: 'Litoral Norte Serviços de Engenharia Ltda', cnpj_root: 36_215_704,
          segment: 'Serviços', sub_segment: 'Engenharia e construção',
          city: 'Niterói', uf: 'RJ', responsible: 'Luciana Prado',
          tier: :pequeno, company_count: 2, carrier_keys: %i[vertice ipiranga],
          base_volume: 383_000.0, closing_date_offset: -298, active_from: -23,
          story: :estavel
        },
        {
          index: 11, slug: 'fundicao-tres-rios', name: 'Fundição Três Rios',
          formal: 'Fundição Três Rios Indústria Metalúrgica Ltda', cnpj_root: 24_580_931,
          segment: 'Indústria', sub_segment: 'Fundição',
          city: 'Três Rios', uf: 'RJ', responsible: 'Otávio Mendonça',
          tier: :recuperacao, company_count: 2, carrier_keys: %i[vertice ipiranga],
          base_volume: 1_465_000.0, closing_date_offset: -833, active_from: -23,
          story: :dificuldade
        },
        {
          index: 12, slug: 'tecnologia-ribeirao', name: 'Tecnologia Ribeirão',
          formal: 'Ribeirão Tecnologia e Serviços Ltda', cnpj_root: 47_336_122,
          segment: 'Serviços', sub_segment: 'Tecnologia da informação',
          city: 'Ribeirão Preto', uf: 'SP', responsible: 'Beatriz Nogueira',
          tier: :entrante, company_count: 1, carrier_keys: %i[aurora],
          base_volume: 296_000.0, closing_date_offset: -46,
          # Entra faltando 2 meses para o fim da série. É o cliente que prova que
          # o gráfico não quebra com histórico curto.
          active_from: -1, story: :entrante
        }
      ].freeze

      # Quantos borderôs por mês, por porte. Faixa de `demo-seed-design.md` §6.
      BORDEROS_PER_MONTH = {
        grande: [12, 16],
        medio: [9, 13],
        pequeno: [6, 10],
        recuperacao: [5, 10],
        entrante: [4, 7]
      }.freeze

      module_function

      def carriers
        @carriers ||= CARRIERS.map { |attrs| Records::Carrier.new(**attrs) }
      end

      def carrier(key)
        carriers.find { |c| c.key == key }
      end

      def clients(base_date)
        CLIENTS.map do |attrs|
          data = attrs.dup
          offset = data.delete(:closing_date_offset)
          Records::Client.new(**data, closing_date: base_date + offset)
        end
      end

      # Empresas do grupo. A **raiz do CNPJ é a do grupo**; o que muda é o número
      # de ordem da filial, com o dígito verificador recalculado — que é como
      # funciona de verdade.
      def companies_for(client)
        used = []

        (1..client.company_count).map do |branch|
          title = company_title(client, branch, used)
          used << title

          Records::Company.new(
            key: "#{client.slug}-#{branch}",
            client: client,
            title: title,
            branch: branch,
            cnpj: Support::Br.cnpj(client.cnpj_root, branch)
          )
        end
      end

      # **O título é ÚNICO dentro do projeto** — `companies` tem índice único
      # `(project_id, title)`, e é essa a chave natural do escritor.
      #
      # O `used` não é zelo preventivo: o grupo cuja razão social já termina em
      # "Participações S.A." colidia com a própria filial 2, porque o sufixo
      # sorteado para ela é exatamente esse. As duas empresas viravam **uma** linha
      # no banco, e a segunda sobrescrevia a primeira em toda execução — o seed
      # reportava "atualizado" para sempre e o limite de uma delas sumia. Achado
      # pela contagem da segunda rodada, não por erro: o banco aceitava.
      def company_title(client, branch, used = [])
        return client.formal if branch == 1

        base = client.name.sub(/\AGrupo\s+/, '')
        suffixes = Support::Br::COMPANY_SUFFIXES.rotate(branch - 1)
        suffix = suffixes.find { |s| !used.include?("#{base} #{s}") } || suffixes.first

        "#{base} #{suffix}"
      end
    end
  end
end
