# frozen_string_literal: true

module Demo
  module Writers
    # Indicadores e as entradas mensais. Chave natural:
    # `(project_id, indicator_id, year, month)` — o índice único da S10.
    #
    # **É aqui que a cadeia fecha visivelmente.** O valor de "Volume operado" de um
    # mês não é um número novo: é a soma dos `vlr_bruto_final` dos borderôs
    # daquele mês, calculada uma vez no razão e usada nos dois lugares. Se o
    # painel mostrar R$ 4,18 mi, a lista de borderôs filtrada por aquele mês soma
    # R$ 4,18 mi — que é exatamente a conferência que o cliente faz.
    #
    # `nil ≠ 0`: mês sem operação **não recebe linha**. Gravar zero faria o
    # gráfico do cliente #12 (2 meses de histórico) mostrar 22 meses de fundo do
    # poço em vez de uma série curta.
    class Indicators < Base
      def self.requires = %w[Indicator IndicatorEntry]
      def self.owner_slice = 'S10'

      # Só os indicadores em **dinheiro** viram linha: `Indicator::VALUE_TYPES`
      # tem um elemento só hoje (Q-R32). Ver a nota em
      # `Ledger::Ancillary::INDICATORS` — o resto do razão já está pronto e passa
      # a ser gravado quando a S10 aceitar os outros tipos.
      MONEY = 'currency'

      def call
        indicators = ensure_indicators!
        connect_projects!(indicators)
        especificos = ensure_project_indicators!
        announce_pending_types

        ledger.indicator_entries.each do |entry|
          project = project_for(entry.client)
          indicator = if entry.project_specific
                        especificos[[entry.client.slug, entry.indicator_key]]
                      else
                        indicators[entry.indicator_key]
                      end
          next if project.nil? || indicator.nil?

          upsert!(::IndicatorEntry,
                  find_by: { project_id: project.id, indicator_id: indicator.id,
                             year: entry.year, month: entry.month },
                  # `title`, `key` e `value_type` **não** são escritos aqui: o
                  # lançamento os copia do indicador num `before_validation`
                  # (T-D11). Mandá-los junto faria o escritor propor um valor que
                  # o model reescreve, e o seed reportaria "atualizado" a cada
                  # execução — a mesma armadilha do
                  # `subordinated_accounts_percent` do carrier.
                  attributes: { value: entry.value })
        end
      end

      private

      def money_indicators
        Ledger::Ancillary::INDICATORS.select { |i| i[:value_type] == MONEY }
      end

      # **Não é pendência de fatia — é o espelho da produção.** A mensagem dizia
      # "aguardam a S10", e o dump de 31/05/2025 desmentiu: `value_type` é
      # `"Dinheiro"` em **529 de 529** indicadores. Ver a nota longa em
      # `Ledger::Ancillary::INDICATORS`.
      def announce_pending_types
        pending = Ledger::Ancillary::INDICATORS.reject { |i| i[:value_type] == MONEY }
        return if pending.empty?

        io.puts "   · #{pending.size} indicadores do razão não são de dinheiro e NÃO são gravados: " \
                "#{pending.map { |i| i[:title] }.join(', ')}. Produção só tem " \
                "«#{::Indicator::VALUE_TYPE_MONEY}» (529/529 no dump) — é espelho, não lacuna."
      end

      # Indicadores **globais** (`project_id IS NULL`): os mesmos para todos os
      # clientes é o que permite comparar carteira contra carteira, que é a tela
      # que a gestora usa.
      #
      # O título vai **já normalizado** (DEC-89 grava em caixa alta e sem acento
      # em todo save). Mandá-lo como se escreve faria `record.changed?` ser
      # verdadeiro em toda execução, contra um valor que o model ia normalizar de
      # volta para o mesmo texto — "1 atualizado" eterno, sem nenhuma mudança.
      def ensure_indicators!
        money_indicators.to_h do |indicator|
          record = upsert!(::Indicator, find_by: { project_id: nil, key: indicator[:key] },
                                        attributes: {
                                          title: I18n.transliterate(indicator[:title]).upcase,
                                          value_type: ::Indicator::VALUE_TYPE_MONEY,
                                          is_active: true
                                        })
          [indicator[:key], record]
        end
      end

      # **Os indicadores ESPECÍFICOS de projeto** (`scope: "project"`).
      #
      # Produção tem 527 específicos contra 2 globais; o seed tinha 5 globais e
      # **zero** específico, e a coluna "Alcance" da tela dizia "Global" em
      # todas as linhas — um selo que nunca muda não demonstra que existe
      # diferença. Ver `Ledger::Ancillary::PROJECT_INDICATORS`.
      #
      # **A conexão vem junto, e não é decoração:** `Indicators::IndicatorService`
      # cria a `ProjectIndicatorConnection` do indicador com o próprio projeto
      # no mesmo `transaction` da criação (`indicator_service.rb:92-97`). Sem ela
      # o indicador existiria e **não apareceria na grade** — que é o defeito
      # que o Q-R31 descreve, chegando pela porta do seed.
      #
      # A `key` é passada explicitamente porque `derive_key` só age quando ela
      # vem em branco: fixá-la aqui é o que faz a segunda execução reencontrar a
      # linha em vez de criar outra.
      def ensure_project_indicators!
        return {} unless defined?(::Indicator)

        ledger.clients.each_with_object({}) do |client, acc|
          project = project_for(client)
          next if project.nil?

          Ledger::Ancillary::PROJECT_INDICATORS.fetch(client.slug, []).each do |indicator|
            record = upsert!(::Indicator,
                             find_by: { project_id: project.id, key: indicator[:key] },
                             attributes: {
                               title: I18n.transliterate(indicator[:title]).upcase,
                               value_type: ::Indicator::VALUE_TYPE_MONEY,
                               is_active: true
                             })
            connect!(project, record)
            acc[[client.slug, indicator[:key]]] = record
          end
        end
      end

      def connect!(project, indicator)
        return unless defined?(::ProjectIndicatorConnection)

        upsert!(::ProjectIndicatorConnection,
                find_by: { project_id: project.id, indicator_id: indicator.id },
                attributes: {})
      end

      def connect_projects!(indicators)
        return unless defined?(::ProjectIndicatorConnection)

        ledger.clients.each do |client|
          project = project_for(client)
          next if project.nil?

          indicators.each_value do |indicator|
            upsert!(::ProjectIndicatorConnection,
                    find_by: { project_id: project.id, indicator_id: indicator.id },
                    attributes: {})
          end
        end
      end
    end
  end
end
