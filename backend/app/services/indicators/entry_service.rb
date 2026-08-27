# frozen_string_literal: true

module Indicators
  # S10 / BE-324, BE-326, BE-327, BE-328, BE-716 — **o serviço único da grade**
  # (contrato **C2**).
  #
  # A montagem da grade e a gravação da célula passam **pelo mesmo objeto**. No
  # legado elas não se conheciam: a leitura era feita **dentro da view**
  # (`indicator_entries/list/_widget.html.erb:14`, uma consulta por célula) e a
  # escrita era um `$.ajax` por campo, sem handler de erro. É por isso que uma
  # célula podia mostrar `0` para um mês que nunca foi lançado, e mostrar
  # "salvo" para uma gravação que o servidor recusou.
  #
  # ## `#grid` — de 12 consultas por indicador para uma (BE-324)
  #
  # O legado chama `project.indicator_entry_on_month_and_indicator(m, year, i)`
  # (`project.rb:424`) dentro de dois laços aninhados: **12 consultas por
  # indicador**, e o mesmo método é chamado **duas vezes** por célula (linha 14
  # do widget: uma no teste `.blank?` e outra no valor) — ou seja, 24 idas ao
  # banco por indicador no modo "todos os meses". Com 3 indicadores são
  # **72 consultas** para desenhar uma tela.
  #
  # Aqui é **uma** consulta de entries para o período inteiro, e a grade é
  # montada em memória. **A otimização não muda o resultado** e há teste
  # provando: `spec/services/indicators/entry_service_spec.rb` compara a grade
  # com a montagem ingênua célula a célula, linha a linha.
  #
  # Corrige junto:
  #
  # - **a ordenação alfabética descartada em silêncio.**
  #   `indicator_entries_controller.rb:24` faz `@indicators.order(title: :asc)`
  #   **sem reatribuir** — o resultado é jogado fora e a grade sai na ordem que o
  #   banco devolver;
  # - **`project_id` inválido → 500.** `Project.where(id: ...).first` (`:20`)
  #   devolve `nil` e a linha seguinte faz `nil.indicators`. Aqui o projeto é o
  #   `current_project!`, que já responde 404.
  #
  # ## "Não lançado" ≠ "lançado como zero" (DEC-70)
  #
  # A célula sem lançamento vem com `entry: nil`; a lançada com zero vem com
  # `value: "0.0"`. **A distinção nasce aqui, não numa heurística do
  # componente** — se o front tivesse que adivinhar, a ambiguidade voltaria na
  # primeira refatoração. No legado a view instanciava um `IndicatorEntry.new`
  # para o mês vazio e renderizava `entry.value.blank? ? 0 : entry.value`, e como
  # a coluna tem default `0.0` os dois saíam idênticos.
  #
  # **Exceção consciente ao DEC-30**, pelo critério escrito na própria DEC-70:
  # não há número a preservar — a grade **não tem linha nem coluna de total**
  # (verificado no widget), então distinguir não muda soma nenhuma.
  #
  # ## Fora de escopo, e isto é contrato (DEC-09)
  #
  # **Não existe** variação (mês a mês, ano a ano, percentual), acumulado, média
  # nem gráfico em lugar nenhum do legado, e o `dash` não referencia indicadores.
  # Isso é requisito NOVO (`NEW-001`, fatia **S15**), não paridade — o QA do
  # Phase 4 não deve procurá-lo no legado. A S15 consome **este** serviço; nenhuma
  # agregação nova nasce no cliente (contrato C2).
  class EntryService
    class << self
      include ApiResponseHandler

      MONTHS = (1..12).to_a.freeze

      # --- A grade ----------------------------------------------------------

      # Devolve **indicadores** (não entries), cada um com as células do período.
      #
      #   [{ indicator: <Indicator>, cells: [{ month: 1, entry: <IndicatorEntry|nil> }, …] }]
      #
      # `month:` nulo → os 12 meses. `month:` preenchido → uma célula só (é o
      # modo "mês único" da tela).
      def grid(project:, year:, month: nil, indicator_id: nil)
        year = year.to_i
        months = month.present? ? [month.to_i] : MONTHS

        indicators = grid_indicators(project: project, indicator_id: indicator_id)
        entries = entries_index(project: project, year: year, months: months,
                                indicator_ids: indicators.map(&:id))

        indicators.map do |indicator|
          {
            indicator: indicator,
            cells: months.map { |m| { month: m, entry: entries[[indicator.id, m]] } }
          }
        end
      end

      # Os indicadores que a grade mostra: os **conectados** ao projeto, vivos e
      # **ativos**, em ordem alfabética. É o `@project.indicators.where(is_active: 1)`
      # do legado (`indicator_entries_controller.rb:21-24`) com a ordenação
      # efetivamente aplicada.
      def grid_indicators(project:, indicator_id: nil)
        scope = project.indicators.kept.active
        scope = scope.where(indicators: { id: indicator_id }) if indicator_id.present?
        scope.order(title: :asc).to_a
      end

      # --- Escrita ----------------------------------------------------------

      # `BE-326` — **upsert** por (projeto, indicador, ano, mês).
      #
      # Três coisas mudam, e as três são defeito medido:
      #
      # 1. **`user_id` passa a vir do servidor.** No legado ele vem do formulário
      #    (`_widget.html.erb:18`, campo escondido) e está no `permit`
      #    (`indicator_entries_controller.rb:107`): dava para registrar
      #    lançamento em nome de outro usuário forjando o campo.
      # 2. **É upsert, não create.** Sem índice único no banco havia corrida; e
      #    quando outra aba já tinha criado a linha, o POST falhava com "já está
      #    em uso" em vez de atualizar — o usuário via o campo destravar sem
      #    mensagem (não havia handler de erro) e **acreditava que salvou**.
      # 3. **`project_id` vem do escopo**, nunca do corpo (C1).
      def upsert(project:, indicator_id:, year:, month:, value:, actor: nil)
        indicator = connected_indicator(project, indicator_id)
        return { status: 404, error: 'Indicador não encontrado neste projeto.' } if indicator.nil?

        entry = IndicatorEntry.find_or_initialize_by(
          project_id: project.id, indicator_id: indicator.id, year: year.to_i, month: month.to_i
        )
        criando = entry.new_record?
        entry.value = value
        entry.created_by = actor&.id if criando
        entry.updated_by = actor&.id

        return unprocessable(entry) unless save_safely(entry)

        { status: criando ? 201 : 200, data: entry }
      end

      # `BE-327`. `indicator_id` nulo devolve **422**, não 500 (no legado
      # `self.indicator.title` levantava `NoMethodError` no `before_validation`).
      #
      # Mover o lançamento de período (`month`/`year`/`indicator_id`) deixa de
      # ser silencioso: a mudança fica na trilha do log. `project_id` **nunca**
      # muda — trocar o tenant de um lançamento por campo de formulário é a
      # família D-23.
      def update(project:, id:, attrs:, actor: nil)
        entry = find(project, id)
        return not_found if entry.nil?

        antes = entry.slice('indicator_id', 'year', 'month', 'value')

        entry.value = attrs[:value] if attrs.key?(:value)
        entry.year = attrs[:year] if attrs.key?(:year)
        entry.month = attrs[:month] if attrs.key?(:month)
        if attrs.key?(:indicator_id)
          indicator = connected_indicator(project, attrs[:indicator_id])
          return { status: 422, error: 'Indicador não encontrado neste projeto.' } if indicator.nil?

          entry.indicator = indicator
        end
        entry.project_id = project.id
        entry.updated_by = actor&.id

        return unprocessable(entry) unless save_safely(entry)

        depois = entry.slice('indicator_id', 'year', 'month', 'value')
        if antes.except('value') != depois.except('value')
          Rails.logger.info("[Indicators] #{actor&.id} moveu o lançamento #{entry.id}: #{antes} → #{depois}")
        end

        { status: 200, data: entry }
      end

      # `BE-328` / **DEC-71** — o endpoint existe, **a tela não tem botão**.
      #
      # No legado a rota existe (`routes.rb:84`) e a action também
      # (`indicator_entries_controller.rb:75-85`), mas **nenhuma view a chama**:
      # zero ocorrências de excluir/remover/`data-method: :delete` na pasta de
      # lançamentos. Na prática "zerar" é digitar `0`, e o registro continua
      # existindo. A DEC-71 resolveu o conflito de default escolhendo portar o
      # endpoint **sem** botão.
      #
      # Com a DEC-70 junto, apagar passa a ter efeito visível de verdade: a
      # célula volta ao estado **"não lançado"**, que agora é distinguível de
      # zero. Antes das duas decisões, excluir e zerar produziam a mesma tela.
      #
      # Vale a condição 1 do DEC-53: endpoint sem tela continua alcançável por
      # URL e **precisa de autorização e escopo de projeto** como qualquer outro.
      def destroy(project:, id:, actor: nil)
        entry = find(project, id)
        return not_found if entry.nil?

        unless entry.destroy
          return { status: 422, error: entry.errors.full_messages.to_sentence,
                   details: entry.errors.messages }
        end

        Rails.logger.info("[Indicators] #{actor&.id} apagou o lançamento #{id} do projeto #{project.id}")
        { status: 200, data: { deleted: true, id: id.to_s } }
      end

      # --- As 4 consultas do legado, e só elas (BE-716) ---------------------
      #
      # Portadas de `../sfg/app/models/project.rb:424-441`. Duas delas
      # (`entries_on_month` e `entries_on_indicator`) **não têm nenhum chamador**
      # no legado: vêm como domínio coberto por teste, **sem endpoint**, porque
      # o DEC-09 manda portar o que existe e o DEC-53 proíbe expor superfície que
      # ninguém pediu.
      #
      # **Nada de variação, acumulado, média ou gráfico** — ver o cabeçalho.

      # `project.indicator_entry_on_month_and_indicator(month, year, indicator)`
      def entry_on_month_and_indicator(project:, indicator:, month: Date.current.month, year: Date.current.year)
        IndicatorEntry.for_project(project)
                      .for_indicator(indicator)
                      .find_by(month: month, year: year)
      end

      # `project.indicator_entries_on_month(month, year)` — **sem chamador**.
      def entries_on_month(project:, month: Date.current.month, year: Date.current.year)
        IndicatorEntry.for_project(project).where(month: month, year: year)
      end

      # `project.indicator_entries_on_indicator(indicator)` — **sem chamador**.
      def entries_on_indicator(project:, indicator:)
        IndicatorEntry.for_project(project).for_indicator(indicator)
      end

      # `project.all_indicator_entries_on_month(month, year)` — materializa os
      # meses não lançados.
      #
      # ⚠ **A única das quatro em que o resultado muda, e é a DEC-70.** O legado
      # devolve, para o indicador sem lançamento, um `IndicatorEntry.new(value: 0)`
      # — ou seja, **inventa um zero**. Aqui o não lançado vem como `nil`, e é o
      # chamador que decide como mostrar. Nenhuma soma muda: a grade não tem
      # total, e este método não tem outro consumidor no legado além da grade.
      def all_entries_on_month(project:, month: Date.current.month, year: Date.current.year)
        indicators = project.indicators.kept.order(title: :asc).to_a
        index = entries_index(project: project, year: year, months: [month.to_i],
                              indicator_ids: indicators.map(&:id))

        indicators.map { |i| { indicator: i, entry: index[[i.id, month.to_i]] } }
      end

      # --- Peças ------------------------------------------------------------

      def find(project, id)
        return nil unless id.to_s.match?(ProjectScopedService::UUID_FORMAT)

        IndicatorEntry.for_project(project).find_by(id: id)
      end

      private

      # **A consulta única.** Chave `[indicator_id, month]`.
      def entries_index(project:, year:, months:, indicator_ids:)
        return {} if indicator_ids.empty?

        IndicatorEntry.for_project(project)
                      .where(indicator_id: indicator_ids, year: year, month: months)
                      .index_by { |e| [e.indicator_id, e.month] }
      end

      # O indicador precisa estar **conectado** ao projeto. Id de indicador de
      # outro projeto, ou global não conectado, simplesmente não é encontrado.
      def connected_indicator(project, indicator_id)
        return nil unless indicator_id.to_s.match?(ProjectScopedService::UUID_FORMAT)

        project.indicators.kept.find_by(indicators: { id: indicator_id })
      end

      def save_safely(record)
        record.save
      rescue ActiveRecord::RecordNotUnique => e
        # Corrida entre duas abas: o índice único do banco venceu. Vira 422 com
        # texto de humano, não 500.
        Rails.logger.info("[Indicators] índice único recusou o lançamento: #{e.message}")
        record.errors.add(:base, 'Já existe um lançamento para este indicador neste período.')
        false
      end

      def not_found
        { status: 404, error: 'Lançamento não encontrado.' }
      end

      def unprocessable(record)
        { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
      end
    end
  end
end
