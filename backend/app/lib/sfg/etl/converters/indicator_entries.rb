# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `indicator_entries` (legado) -> `IndicatorEntry` (ai9). S10.
      #
      # É a maior tabela da unidade (projetos × indicadores × 12 × anos).
      #
      # ## Não há conversão de fuso a fazer no PERÍODO. Medido.
      #
      # A conversão UTC-2 (2016–2019) / UTC-3 (2020+) que a S14 mediu vale para os
      # **timestamps** (`created_at`/`updated_at`), e é por isso que eles passam por
      # `Values.to_utc`. Mas o **bucket do mês não vem de timestamp nenhum**: o
      # usuário digita o valor numa célula que já sabe o seu mês e o seu ano
      # (`indicator_entries/list/_widget.html.erb:21-22`, campos escondidos `month`
      # e `year`), e as quatro consultas do legado (`project.rb:424-441`) filtram
      # por `where(month:, year:)` — inteiros. **Não existe virada de mês a errar
      # aqui**, e converter `year`/`month` seria inventar um deslocamento.
      #
      # ## `user_id` vira `created_by`
      #
      # No legado é uma coluna só, e ela vem **do formulário** (está no `permit`,
      # `indicator_entries_controller.rb:107`). Na origem ela é o melhor registro
      # disponível de "quem lançou", então vira `created_by`. **`updated_by` fica
      # nulo**: o legado não guardava quem alterou por último, e preenchê-lo com o
      # mesmo id seria afirmar algo que o dado não diz.
      #
      # ## A foto denormalizada é COPIADA da origem, não recalculada
      #
      # `title`, `key` e `value_type` são preenchidos com o que está gravado na
      # linha do legado — não com o do indicador atual. Recalcular na carga
      # antecipar o efeito do `after_save` (T-D11) e apagaria a diferença que o
      # relatório de reconciliação existe para mostrar. O model reescreve o
      # histórico quando alguém renomeia o indicador **depois**, que é o
      # comportamento replicado; a carga não faz isso por conta própria.
      #
      # ## Mês fora da faixa
      #
      # O legado não valida faixa nenhuma: mês 13 ou ano 0 passam e explodem depois
      # em `Date.new(year, month)`. O ai9 tem CHECK no banco, então uma linha assim
      # **derrubaria a carga**. `anomalies` a reporta no dry-run, que é o momento de
      # decidir o que fazer com ela.
      class IndicatorEntries < Base
        def self.source_table = 'indicator_entries'
        def self.target_model = 'IndicatorEntry'
        def self.requires = %w[IndicatorEntry Indicator]
        def self.owner_slice = 'S10'

        def self.references = {
          'project_id' => 'projects',
          'indicator_id' => 'indicators',
          'user_id' => 'livetat_auth_users'
        }

        def self.uniques = [%w[project_id indicator_id year month]]
        def self.sums = %w[value]

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            indicator_id: ref('indicators', row['indicator_id']),
            year: row['year'],
            month: row['month'],
            value: Values.to_decimal(row['value']),
            title: row['title'],
            key: row['key'],
            value_type: row['value_type'].presence || Indicator::VALUE_TYPE_MONEY,
            created_by: ref('livetat_auth_users', row['user_id']),
            updated_by: nil,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          linhas = []
          mes = row['month'].to_i
          ano = row['year'].to_i

          unless IndicatorEntry::MONTHS.cover?(mes)
            linhas << Values.anomaly_line('mês fora de 1..12 — o CHECK do ai9 recusa esta linha',
                                          'indicator_entries', row['id'], 'month', row['month'])
          end
          unless IndicatorEntry::YEARS.cover?(ano)
            linhas << Values.anomaly_line('ano fora de 1900..2999 — o CHECK do ai9 recusa esta linha',
                                          'indicator_entries', row['id'], 'year', row['year'])
          end
          if row['value'].nil?
            linhas << Values.anomaly_line('valor nulo — zero é lançamento, nulo não é (BE-329)',
                                          'indicator_entries', row['id'], 'value', nil)
          end

          linhas.concat(sem_conexao(row))
        end

        # **DEC-129.3 — lançamento sem conexão é dado que carrega e nunca aparece.**
        #
        # Medido no dump de 31/05/2025: **51 lançamentos** em **13 pares**
        # (projeto, indicador) sem linha em `project_indicator_connections`. A
        # grade do ai9 é montada pelas conexões (é a ausência dela que faz o
        # indicador sumir da tela sem apagar lançamento nenhum — Q-R31), então
        # esses 51 carregariam e **nunca apareceriam**.
        #
        # Se há lançamento, alguém usou aquele indicador naquele projeto: o que
        # sumiu foi a conexão. Ela é recriada em `post_load!`; aqui a linha só
        # sai LISTADA, com chave de decisão própria.
        def sem_conexao(row)
          par = [row['project_id'].to_s, row['indicator_id'].to_s]
          return [] if par.any?(&:empty?)
          return [] if pares_conectados.include?(par)

          [{
            key: 'indicator_entries:connection_missing',
            title: 'DEC-129.3 — lançamento de indicador sem conexão (projeto, indicador)',
            line: Values.anomaly_line(
              "lançamento existe para o par (projeto #{row['project_id']}, indicador "               "#{row['indicator_id']}) que NÃO tem conexão na origem. A grade é montada pelas "               'conexões: sem ela este lançamento carrega e nunca aparece. A conexão é CRIADA '               'ao fim da carga (`post_load!`).',
              self.class.source_table, row['id'], 'project_id/indicator_id', nil
            )
          }]
        end

        # Os pares que a origem TEM conectados. Lido uma vez, na primeira
        # pergunta — a tabela tem 590 linhas e a de lançamentos tem 6.174.
        def pares_conectados
          @pares_conectados ||= begin
            tabela = 'project_indicator_connections'
            linhas = run.source.table?(tabela) ? run.source.ordered_rows(tabela) : []
            linhas.map { |l| [l['project_id'].to_s, l['indicator_id'].to_s] }.to_set
          end
        end

        # **DEC-129.3 — criar a conexão que falta, depois de os lançamentos entrarem.**
        #
        # Roda no DESTINO, não na origem: qualquer par (projeto, indicador) que
        # tenha lançamento carregado e não tenha conexão ganha uma. É por isso que
        # o gancho é deste conversor e não do de conexões — `IndicatorEntries` é o
        # último dos três na ordem de carga (`load_order.yml`), e no momento em que
        # `ProjectIndicatorConnections` roda ainda não há lançamento a conferir.
        #
        # A conexão criada nasce **sem `legacy_id`**, porque ela não existe na
        # origem — e é isso que a distingue das 590 migradas, sem precisar de
        # coluna nova.
        #
        # `find_or_create_by!` mantém o gancho idempotente: uma segunda execução
        # (`RESUME=0`) não escreve nada.
        def self.post_load!
          return { criadas: 0 } unless model_ready?('IndicatorEntry') &&
                                       model_ready?('ProjectIndicatorConnection')

          conectados = ::ProjectIndicatorConnection.pluck(:project_id, :indicator_id).to_set
          faltantes = ::IndicatorEntry.distinct.pluck(:project_id, :indicator_id)
                                      .reject { |par| conectados.include?(par) }

          criadas = faltantes.map do |project_id, indicator_id|
            ::ProjectIndicatorConnection.find_or_create_by!(project_id: project_id, indicator_id: indicator_id)
            "projeto=#{project_id} indicador=#{indicator_id}"
          end

          {
            criadas: criadas.size,
            pares: criadas,
            note: if criadas.empty?
                    'DEC-129.3: todo lançamento carregado já tinha conexão. Nada a restaurar.'
                  else
                    "DEC-129.3: #{criadas.size} conexão(ões) CRIADA(S) para pares que tinham lançamento e "                       'não tinham conexão. Sem elas o lançamento carrega e nunca aparece na grade — '                       'dado migrado que a interface não alcança é dado perdido na prática.'
                  end
          }
        end
      end
    end
  end
end
