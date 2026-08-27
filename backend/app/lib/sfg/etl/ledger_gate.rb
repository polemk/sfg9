# frozen_string_literal: true

module Sfg
  module Etl
    # S14 / tarefa **10.7** — **o portão do RAZÃO.**
    #
    # A conferência final de fechamento tinha três critérios e **nenhuma
    # ferramenta**: contava-se `to-remove`, `build?` e item aberto sem dono na
    # mão, num arquivo de ~1.900 linhas que muda várias vezes por dia enquanto
    # há fatia em voo. Contagem manual de alvo móvel não é conferência: é uma
    # foto que envelhece antes de alguém ler.
    #
    # A S14 já tinha as outras duas metades do fechamento — `sfg_etl:schema_gate`
    # (nenhuma tabela no `schema.rb` sem migration que a crie) e a seção "Tabelas
    # com dado e SEM dono declarado" da introspecção (nenhum dado órfão). Faltava
    # a terceira: **nenhum ID do inventário aberto sem dono**. É esta.
    #
    # ## O que ele NÃO faz, de propósito
    #
    # Ele **não marca nada**. Não promove, não adota, não fecha. Ele lê, conta e
    # reprova. Quem marca é a fatia dona, com evidência — a régua da migração é
    # "comparado com dado de produção e bateu", e um portão que marcasse sozinho
    # transformaria o razão em ficção.
    class LedgerGate
      LEDGER = '.migration-ai9/parity-ledger.md'

      # A legenda declarada no cabeçalho do razão. Um status fora dela é erro de
      # digitação, e erro de digitação some da contagem em silêncio — por isso
      # ele é reportado, e não ignorado.
      STATUSES = %w[pending in-progress migrated verified dropped blocked].freeze
      ABERTOS = %w[pending in-progress blocked].freeze
      SEM_DONO = ['', '-', '—', '–'].freeze

      # ⚠ **O razão NÃO tem coluna de estratégia.** O cabeçalho é
      # `| ID | Feature | State | ai9 target | Test | Note |`, e `build`,
      # `build?`, `drop` e `to-remove` vivem **dentro da Note** ou da Feature.
      # Procurar numa coluna que não existe devolve zero achado e um portão
      # verde por engano — foi o que aconteceu na primeira versão deste arquivo.
      Row = Struct.new(:line, :id, :status, :target, :test, :note, :feature, keyword_init: true) do
        def aberto? = ABERTOS.include?(status)
        def sem_dono? = SEM_DONO.include?(note.to_s.strip)
        def texto = "#{feature} #{note}"
        def menciona?(termo) = texto.include?(termo)
      end

      def initialize(path = nil)
        @path = Pathname.new(path || Rails.root.join('..', LEDGER))
      end

      def rows
        @rows ||= @path.readlines.each_with_index.filter_map do |line, i|
          next unless line.start_with?('|')

          # `strip` ANTES do `split`: sem ele o último pedaço é "\n", que não é
          # vazio, sobrevive ao descarte de vazios finais do `split` e vira uma
          # nota em branco — o portão passaria a acusar 213 `dropped` sem
          # evidência que têm evidência. Achado rodando.
          cells = line.strip.split('|').map { |c| c.strip.delete('`*') }
          next if cells.size < 6

          id = cells[1]
          # Só o inventário. A tabela de "features novas" (`NEW-*`) tem legenda
          # própria (`new`) e não é ID de paridade — contá-la faria o portão
          # reprovar por status fora da legenda todo dia, e portão que reprova
          # sempre é portão desligado.
          next unless id&.match?(/\A(BE|FE|DB|OPS|ENG)-\d+\z/)

          Row.new(line: i + 1, id: id, status: cells[3], target: cells[4],
                  test: cells[5], note: cells[-1], feature: cells[2])
        end
      end

      def counts = rows.group_by(&:status).transform_values(&:size).sort.to_h
      def status_desconhecido = rows.reject { |r| STATUSES.include?(r.status) }
      def to_remove = rows.select { |r| r.menciona?('to-remove') || r.status == 'to-remove' }
      def build_interrogacao = rows.select { |r| r.menciona?('build?') }
      def abertos = rows.select(&:aberto?)
      def abertos_sem_dono = abertos.select(&:sem_dono?)
      def dropped_sem_evidencia = rows.select { |r| r.status == 'dropped' && r.sem_dono? }

      # Os três critérios da 10.7, mais dois que a conferência manual não tinha.
      def verdict
        {
          'nenhum `to-remove`' => to_remove.empty?,
          'nenhum `build?` sem resolução escrita' =>
            build_interrogacao.all? { |r| r.note.to_s.match?(/RESOLVID|fechad|dropped/i) },
          'nenhum item aberto sem dono' => abertos_sem_dono.empty?,
          'nenhum `dropped` sem evidência' => dropped_sem_evidencia.empty?,
          'nenhum status fora da legenda' => status_desconhecido.empty?
        }
      end

      def passed? = verdict.values.all?

      def report!(report = Report.new('ledger_gate'))
        report.meta('razão', @path.to_s)
        report.meta('IDs lidos', rows.size)
        report.meta('placar', counts.map { |k, v| "#{k} #{v}" }.join(' · '))

        verdict.each do |criterio, ok|
          report.section("#{criterio} — #{ok ? 'PASSA' : 'REPROVA'}", severity: ok ? :ok : :abort) do |lines|
            lines.concat(detalhe(criterio))
          end
        end
        report
      end

      private

      def detalhe(criterio)
        case criterio
        when 'nenhum `to-remove`' then linhas_de(to_remove)
        when 'nenhum `build?` sem resolução escrita'
          linhas_de(build_interrogacao.reject { |r| r.note.to_s.match?(/RESOLVID|fechad|dropped/i) })
        when 'nenhum item aberto sem dono' then linhas_de(abertos_sem_dono)
        when 'nenhum `dropped` sem evidência' then linhas_de(dropped_sem_evidencia)
        else linhas_de(status_desconhecido)
        end
      end

      def linhas_de(lista)
        return ['(nada a relatar)'] if lista.empty?

        lista.first(80).map { |r| "- linha #{r.line} · `#{r.id}` · #{r.status} · nota: #{r.note.to_s.slice(0, 90)}" }
      end
    end
  end
end
