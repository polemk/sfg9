# frozen_string_literal: true

module Sfg
  module Etl
    # **Todo relatório do ETL é arquivo, nunca saída de terminal.**
    #
    # O portão de cutover é "relatório anexado e assinado por um humano" (runbook,
    # portões 1–3). Saída de terminal não se anexa, não se compara com a rodada
    # anterior e não sobrevive ao fechamento do shell. Arquivo sim.
    #
    # Grava em `tmp/etl/` (fora do versionamento) com carimbo de data **e** mantém
    # um `-latest` estável, para que o runbook possa citar um caminho fixo.
    class Report
      Section = Struct.new(:title, :lines, :severity, keyword_init: true)

      # `:reject` é a severidade da **linha recusada** (DEC-127) e existe porque
      # `:abort` e `:warn` não davam conta do caso.
      #
      # * `:abort` é o portão **de antes da escrita**: anomalia sem decisão
      #   registrada trava a carga inteira, e `Run#run_converter` confere
      #   `aborted?` no começo de CADA conversor. Marcar recusa como `:abort`
      #   faria a primeira linha inválida bloquear todos os conversores
      #   seguintes — que é exatamente o defeito que a DEC-127 mandou consertar.
      # * `:warn` não serve porque não muda o resultado: a carga terminaria
      #   dizendo "sem bloqueio" com linhas de cliente faltando no destino.
      #
      # `:reject` é o meio-termo com nome próprio: **não interrompe a carga** (a
      # execução continua e revela todos os casos de uma vez) e **reprova o
      # resultado no fim** (`failed?`), para que ninguém confunda "terminou" com
      # "carregou tudo".
      SEVERITY_ICON = { ok: '·', info: 'i', warn: '!', reject: 'R', abort: 'X' }.freeze

      def initialize(name, io: $stdout, dir: nil)
        @name = name
        @io = io
        @dir = Pathname.new(dir || Rails.root.join('tmp/etl'))
        @sections = []
        @meta = {}
        @started_at = Time.current
      end

      attr_reader :name, :io, :sections

      def meta(key, value)
        @meta[key.to_s] = value
        self
      end

      # `severity: :abort` marca a seção que trava o cutover. Nenhuma seção
      # some do relatório por estar limpa — "zero órfãos" é informação, e a
      # ausência da linha seria lida como "não conferido".
      def section(title, severity: :ok)
        sec = Section.new(title: title, lines: [], severity: severity)
        yield sec.lines if block_given?
        @sections << sec
        sec
      end

      def abort_sections = @sections.select { |s| s.severity == :abort }
      def aborted? = abort_sections.any?

      def reject_sections = @sections.select { |s| s.severity == :reject }
      def rejected? = reject_sections.any?

      # O veredito do relatório. `aborted?` continua significando "parou antes de
      # escrever"; `rejected?` significa "escreveu, mas deixou linha de fora".
      # Os dois reprovam — e é `failed?` que o rake consulta para sair com status
      # de falha.
      def failed? = aborted? || rejected?

      def write!
        @dir.mkpath
        stamp = @started_at.strftime('%Y%m%d-%H%M%S')
        path = @dir.join("#{@name}-#{stamp}.md")
        path.write(render)
        latest = @dir.join("#{@name}-latest.md")
        latest.write(render)
        path
      end

      def render
        out = +"# ETL Safegold — #{@name}\n\n"
        out << "Gerado em #{@started_at.iso8601} (#{Rails.env}).\n\n"
        @meta.each { |k, v| out << "- **#{k}**: #{v}\n" }
        out << "\n"
        @sections.each do |sec|
          out << "## #{SEVERITY_ICON.fetch(sec.severity)} #{sec.title}\n\n"
          out << (sec.lines.empty? ? "(nada a relatar)\n" : sec.lines.map { |l| "#{l}\n" }.join)
          out << "\n"
        end
        out << "---\n\n"
        if aborted?
          out << "**RESULTADO: ABORTA.** #{abort_sections.size} seção(ões) bloqueante(s): " \
                 "#{abort_sections.map(&:title).join('; ')}.\n"
        end
        if rejected?
          out << "**RESULTADO: CARGA INCOMPLETA.** #{reject_sections.size} seção(ões) com linha recusada: " \
                 "#{reject_sections.map(&:title).join('; ')}.\n\n" \
                 'A carga **seguiu** (DEC-127: uma execução revela todos os casos), mas as linhas acima ' \
                 '**não entraram** no destino. Isto reprova o resultado: não assine este relatório como ' \
                 "\"carregou tudo\".\n"
        end
        out << "**RESULTADO: sem bloqueio.**\n" unless failed?
        out
      end

      # Ecoa no terminal um resumo — o arquivo continua sendo o artefato.
      def echo!(path)
        io.puts
        io.puts '=' * 78
        io.puts "Relatório: #{path}"
        @sections.each do |sec|
          io.puts format('  %<icon>s %-58<title>s %<n>4d linha(s)',
                         icon: SEVERITY_ICON.fetch(sec.severity), title: sec.title.slice(0, 58),
                         n: sec.lines.size)
        end
        io.puts '=' * 78
        io.puts "ABORTA — #{abort_sections.map(&:title).join('; ')}" if aborted?
        if rejected?
          io.puts "CARGA INCOMPLETA — houve linha recusada em #{reject_sections.size} seção(ões) `R`: " \
                  "#{reject_sections.map(&:title).join('; ')}"
        end
        io.puts 'Sem bloqueio.' unless failed?
        io.puts
      end
    end
  end
end
