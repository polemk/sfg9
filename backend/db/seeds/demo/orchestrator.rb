# frozen_string_literal: true

require_relative 'ledger'
require_relative 'writers/base'
Dir[File.join(__dir__, 'writers', '*.rb')].sort.each { |file| require file }

module Demo
  # Executa os escritores **na ordem de dependência**, pulando com aviso os que
  # ainda não têm model, e devolve um relatório.
  #
  # A ordem da lista abaixo não é estética: é dependência real. `risk_movements`
  # depois de `risk_operations` porque o saldo é o acumulado dos movimentos;
  # `segments` depois de `projects` porque é ele quem preenche `projects.segment_id`,
  # FK lógica enquanto a tabela de segmentos não existir.
  class Orchestrator
    ORDER = [
      Writers::Scaffolding,
      Writers::Users,
      Writers::Projects,
      Writers::Memberships,
      Writers::GuaranteeTypes,
      Writers::Carriers,
      Writers::Segments,
      Writers::Companies,
      Writers::CarrierConnections,
      Writers::Guarantees,
      Writers::RiskControls,
      Writers::ReceivableEntries,
      Writers::RiskOperations,
      Writers::RiskMovements,
      # Depois dos movimentos: a transferência chama `Risk::TransferService`,
      # que refaz as duas cadeias de saldo do par estático — e o par estático
      # já existe desde `risk_controls` (é o `after_create` do limite que o
      # abre).
      Writers::StaticTransfers,
      Writers::StructuredOperations,
      # `remunerations` **depois dos dois catálogos de tipo de operação** — o de
      # risco vem dos seeds de referência (`Writers::Scaffolding`) e o de
      # estruturada é escrito pela linha acima — e **antes de `charges`**: o
      # recibo copia dela a taxa, o título e o `remuneration_id`, e é ela que
      # dá candidato ao gerador de recibos. Invertida a ordem, a tela de recibos
      # de uma cobrança abre sem uma única linha para marcar.
      Writers::Remunerations,
      # `providers` antes de `renegotiations`: `renegotiations.provider_id` é
      # `null: false` e o nome do fornecedor é o que deriva a chave de integração
      # da renegociação.
      Writers::Providers,
      Writers::Renegotiations,
      Writers::Indicators,
      # `availability_templates` antes de `availability_entries` pelo motivo
      # óbvio, e os dois depois de `companies`: o lançamento é a célula
      # (padrão × empresa × data).
      Writers::AvailabilityTemplates,
      Writers::AvailabilityEntries,
      # `charges` depois de `risk_operations`: o recibo é a única ponte entre a
      # cobrança e a operação (D-B11), e ele precisa da operação gravada.
      Writers::Charges,
      # Atendimento. Não é escopado por projeto — é uma caixa só para o sistema
      # inteiro —, então entra por último, sem dependência de nada além do
      # elenco (o autor).
      Writers::AdminMessages,
      Writers::Observers
    ].freeze

    def initialize(ledger: nil, io: $stdout)
      @ledger = ledger || Ledger.new
      @io = io
    end

    attr_reader :ledger, :io

    def run
      header
      results = ORDER.map do |writer_class|
        io.puts "→ #{writer_class.writer_name}"
        result = writer_class.new(ledger, io: io).run
        report_line(result)
        result
      end
      footer(results)
      results
    end

    # Só olha: não escreve nada. É o que responde "o seed está completo?" sem
    # precisar rodar o seed.
    def status
      header
      ORDER.each do |writer_class|
        missing = writer_class.missing_models
        if missing.empty?
          io.puts format('  %<icon>s %-24<name>s pronto', icon: '✔', name: writer_class.writer_name)
        else
          io.puts format('  %<icon>s %-24<name>s aguarda %<models>s%<slice>s',
                         icon: '⏭', name: writer_class.writer_name, models: missing.join(', '),
                         slice: writer_class.owner_slice ? " (#{writer_class.owner_slice})" : '')
        end
      end
      io.puts
      io.puts 'Volumetria que o razão tem pronta para gravar:'
      ledger.summary.each { |key, value| io.puts format('  %-28<k>s %<v>6d', k: key, v: value) }
    end

    private

    def header
      io.puts
      io.puts '=' * 78
      io.puts "Seed de demonstração — S20 / DEC-64   (data-base: #{ledger.base_date})"
      io.puts '=' * 78
    end

    def report_line(result)
      if result.status == :skipped
        io.puts "  ⏭ PULADO — #{result.message}"
      elsif result.status == :failed
        io.puts "  ✖ FALHOU — #{result.message}"
      else
        io.puts format('  ✔ %<c>d criados, %<u>d atualizados, %<n>d inalterados',
                       c: result.created, u: result.updated, n: result.unchanged)
        result.skipped_attributes.each do |attribute|
          io.puts "    · coluna ainda inexistente, ignorada: #{attribute}"
        end
      end
    end

    def footer(results)
      skipped = results.select { |r| r.status == :skipped }
      failed = results.select { |r| r.status == :failed }
      io.puts
      io.puts '-' * 78
      io.puts format('Gravados: %<c>d criados, %<u>d atualizados, %<n>d inalterados.',
                     c: results.sum(&:created), u: results.sum(&:updated), n: results.sum(&:unchanged))
      if skipped.any?
        io.puts "Pulados (#{skipped.size}): #{skipped.map(&:writer).join(', ')}"
        io.puts 'Rode `rake demo:seed` de novo quando a fatia dona entregar — é idempotente.'
      end
      if failed.any?
        io.puts "FALHARAM (#{failed.size}): #{failed.map(&:writer).join(', ')}"
        io.puts 'Cada um voltou atrás sozinho; o resto do seed está gravado.'
      end
      io.puts '-' * 78
    end
  end
end
