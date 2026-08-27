# frozen_string_literal: true

module Availability
  # S11 / BE-117, BE-120, BE-125..128, BE-130, BE-148, BE-149 — **a leitura do
  # painel de disponibilidade**: a grade de um dia e os indicadores do mês.
  #
  # ## Contrato C1 — este serviço fecha o D-01, o pior caso da família
  #
  # `app/controllers/api/v1/project_availability_controller.rb` do legado herda
  # de `ApplicationController` (não do `PubApplicationController`) e faz
  # `Project.find(params[:id] || params[:project_id])` **sem escopo e sem
  # autenticação**: qualquer requisição, sem sessão, lia a disponibilidade de
  # qualquer projeto por id. Não é "o filtro é descartado quando chega um id",
  # como nos irmãos D-16/D-29/D-76/D-100 — é **não havia filtro nenhum**.
  #
  # Aqui o serviço **só recebe um `Project` já resolvido** por `current_project!`
  # no endpoint. Não existe caminho para passar um id.
  #
  # ## Ler a grade NUNCA cria registro (DC-30 / BE-130)
  #
  # `Project#availability_entries_for_date` do legado instancia em memória
  # (`AvailabilityEntry.new`, sem save) — até aí tudo bem. O que criava registro
  # eram os derivados (`parent_entry`, `next_level_entries`, `update_mirror!`),
  # chamados na gravação e — o caso ruim — **antes do `destroy`** no controller.
  # Aqui a leitura é `SELECT` puro: a contagem de `availability_entries` antes e
  # depois de abrir a grade é a mesma, e há um spec que confere isso.
  #
  # ## Consultas agregadas, sem N+1 (BE-120)
  #
  # O legado fazia **uma consulta por padrão ativo** para montar a grade
  # (`project.rb:216-233`, laço `active_temps.each` com `template.entries.where`).
  # Aqui são duas: os padrões e os lançamentos do dia, casados em memória.
  class GridService
    class << self
      # A grade de um dia: **todos** os padrões ativos, cada um com o lançamento
      # existente ou uma célula vazia (não persistida).
      #
      # `company_id` em branco = **consolidação geral** (a `mirror` do legado).
      # `company_id` presente mas de outro projeto → 422, nunca "cai calado na
      # consolidação geral", que é o que o legado fazia (`@company = nil`).
      def grid(project:, date:, company_id: nil, query: nil)
        empresa, erro = resolve_company(project, company_id)
        return erro if erro

        data = parse_date(date)
        return { status: 200, data: { date: nil, company: empresa, rows: [] } } if data.nil?

        padroes = ProjectAvailabilityTemplate.for_project(project).active.in_tree_order.to_a
        padroes = filtrar_por_texto(padroes, query)

        lancamentos = AvailabilityEntry
                      .for_project(project)
                      .where(date: data, company_id: empresa&.id,
                             availability_template_id: padroes.map(&:id))
                      .index_by(&:availability_template_id)

        com_filhos = ids_com_filhos(padroes)

        linhas = padroes.map do |padrao|
          entrada = lancamentos[padrao.id]
          {
            template: padrao,
            entry: entrada,
            has_children: com_filhos.include?(padrao.id),
            editable: editable?(padrao, com_filhos, empresa)
          }
        end

        { status: 200, data: { date: data, company: empresa, rows: linhas } }
      end

      # Os indicadores do painel — o `Project#get_values_hash` do legado
      # (`project.rb:393-421`), réplica linha a linha.
      #
      # **DEC-27:** `by_entry[].total` é `virtual_value`, o **saldo acumulado**.
      # O `values[:total]` do legado — soma bruta de `value` dos padrões base —
      # era calculado e **nunca renderizado** por tela nenhuma; a DEC-27 o
      # classificou como código morto a remover nesta fatia, e ele não está
      # aqui. O que entra no lugar é o **rótulo**: o card diz "Saldo acumulado",
      # para o usuário saber qual das duas métricas está lendo (DEC-26).
      def panel(project:, date: nil, month: nil, year: nil, company_id: nil)
        empresa, erro = resolve_company(project, company_id)
        return erro if erro

        data = parse_date(date)
        inicio, fim, erro_mes = month_range(month, year)
        return erro_mes if erro_mes

        ativos = ProjectAvailabilityTemplate.for_project(project).active
        lancamentos = AvailabilityEntry.for_project(project)
                                       .where(company_id: empresa&.id)
                                       .where(availability_template_id: ativos.select(:id))
        lancamentos = data.present? ? lancamentos.where(date: data) : lancamentos.where(date: inicio..fim)

        # As datas que TÊM lançamento com valor — é o que marca o calendário.
        # No legado esta consulta rodava sobre o intervalo do mês mesmo quando
        # havia data escolhida, então o calendário continuava marcando o mês
        # inteiro. Réplica: o conjunto de datas usa sempre o intervalo.
        datas = AvailabilityEntry.for_project(project)
                                 .where(company_id: empresa&.id)
                                 .where(availability_template_id: ativos.select(:id))
                                 .where(date: inicio..fim)
                                 .where.not(value: 0)
                                 .distinct.order(:date).pluck(:date)

        base = ativos.where(parent_template_id: nil).in_tree_order.to_a
        base_por_id = base.index_by(&:id)
        # **BE-148 / DEC-137 — itera LANÇAMENTOS, não padrões.**
        #
        # O legado faz `base_entries.each` (`project.rb:412`): a lista tem uma
        # entrada por LANÇAMENTO existente no período. O ai9 iterava os padrões
        # base e devolvia um cartão por padrão, inclusive os sem lançamento —
        # com total zero. Duas listas de tamanhos diferentes para o mesmo dia, e
        # um zero que significa "não há lançamento" ocupando o lugar de um zero
        # que significaria "lançaram zero".
        #
        # A ordem continua a da árvore (`in_tree_order`), que é o que a tela
        # espera; o legado a herdava da ordem física da tabela.
        base_lancamentos = lancamentos.where(availability_template_id: base.map(&:id))
                                      .index_by(&:availability_template_id)
        base_com_lancamento = base.select { |padrao| base_lancamentos.key?(padrao.id) }

        {
          status: 200,
          data: {
            dates: datas,
            count: contagem_de_folhas(project, ativos, lancamentos),
            company: empresa,
            by_entry: base_com_lancamento.map do |padrao|
              entrada = base_lancamentos.fetch(padrao.id)
              # `name` vem do LANÇAMENTO (`be.title`), não do padrão: o título é
              # copiado na gravação e é a foto do nome no dia. Renomear o padrão
              # não reescreve o passado — no legado tampouco reescrevia.
              { id: padrao.id, name: entrada.title.presence || padrao.title,
                total: entrada.virtual_value,
                operation_type: padrao.operation_type,
                position_path: padrao.position_path }
            end,
            base_templates: base_por_id.keys
          }
        }
      end

      # As datas do mês que têm lançamento — usadas pelo calendário (FE-122).
      def resolve_company(project, company_id)
        return [nil, nil] if company_id.blank?

        empresa = Company.where(project_id: project.id, id: company_id).first if uuid?(company_id)
        return [empresa, nil] if empresa

        [nil, { status: 422, error: 'Empresa inválida para este projeto.' }]
      end

      private

      def uuid?(value) = value.to_s.match?(ProjectScopedService::UUID_FORMAT)

      def parse_date(value)
        return nil if value.blank?
        return value if value.is_a?(Date)

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Mês inválido responde **422**, não `Date.new(2026, 13, 1)` estourando
      # `ArgumentError` em 500 como no legado (`project_availability_controller.rb:11`).
      def month_range(month, year)
        mes = month.presence&.to_i || Time.zone.today.month
        ano = year.presence&.to_i || Time.zone.today.year

        return [nil, nil, { status: 422, error: 'Mês inválido.' }] unless mes.between?(1, 12)
        return [nil, nil, { status: 422, error: 'Ano inválido.' }] unless ano.between?(1900, 2999)

        inicio = Date.new(ano, mes, 1)
        [inicio, inicio.end_of_month, nil]
      end

      # `values[:count]` do legado: lançamentos com valor ≠ 0 em padrões
      # **folha** — nível 3, ou nível 2 sem filhos. Padrão base (nível 1) fica
      # de fora porque ele é total, não lançamento.
      def contagem_de_folhas(project, ativos, lancamentos)
        nao_base = ativos.where.not(parent_template_id: nil).to_a
        com_filhos = ids_com_filhos(nao_base)
        folhas = nao_base.reject { |t| com_filhos.include?(t.id) }.map(&:id)
        return 0 if folhas.empty?

        lancamentos.where(availability_template_id: folhas).where.not(value: 0).count
      end

      # Uma consulta para saber quais nós têm filho — no legado era
      # `has_child?` por nó, dentro de um `select` em Ruby (N+1).
      def ids_com_filhos(padroes)
        ids = padroes.map { |t| t.respond_to?(:id) ? t.id : t }
        return Set.new if ids.empty?

        Set.new(AvailabilityTemplate.where(parent_template_id: ids).active_ignore_lock
                                    .distinct.pluck(:parent_template_id))
      end

      # **FE-132 / D-23 — o MESMO critério no cliente e no servidor.** No legado
      # o bloqueio da célula era exclusivamente de interface: um `PUT` direto
      # gravava em consolidação geral e em nó com filhos sem nenhuma recusa.
      #
      # A célula é editável quando: há empresa escolhida (consolidação geral é
      # sempre derivada), o nó **não** tem filhos (o valor dele é a soma deles)
      # e o padrão não está bloqueado por job.
      def editable?(padrao, com_filhos, empresa)
        return false if empresa.nil?
        return false if com_filhos.include?(padrao.id)
        return false if padrao.locked?

        true
      end

      def filtrar_por_texto(padroes, query)
        termo = query.to_s.strip
        return padroes if termo.blank?

        alvo = I18n.transliterate(termo).downcase
        padroes.select { |t| I18n.transliterate(t.title.to_s).downcase.include?(alvo) }
      end
    end
  end
end
