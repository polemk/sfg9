# frozen_string_literal: true

module Sfg
  # Log das rotinas de correção de dado (OPS-055, OPS-089).
  #
  # Existe porque o legado corrigia dado colando método no `rails c`: não
  # sobrava registro de **o que** mudou, **quando** nem **de quê para quê**.
  # Descobrir isso depois é impossível — e é o tipo de coisa que só se percebe
  # quando um número não bate seis meses adiante.
  #
  # Escreve nos dois lugares de propósito: no `Rails.logger` (que vai para o
  # agregador) e num arquivo em `log/`, que é o que alguém abre no servidor.
  class FixLog
    attr_reader :nome, :aplicar, :total

    def initialize(nome, aplicar)
      @nome = nome
      @aplicar = aplicar
      @total = 0
      @inicio = Time.current
      @caminho = Rails.root.join('log', "#{nome}-#{@inicio.strftime('%Y%m%d%H%M%S')}.log")
      escrever("== #{nome} — #{aplicar ? 'APLICANDO' : 'PRÉ-VISUALIZAÇÃO (use APPLY=1 para aplicar)'}")
    end

    def linha(alvo, antes, depois)
      @total += 1
      escrever("#{alvo}: #{antes} -> #{depois}")
    end

    def encerrar!
      escrever("== #{total} linha(s) #{aplicar ? 'alteradas' : 'seriam alteradas'} em #{(Time.current - @inicio).round(2)}s")
      escrever("== log: #{@caminho}") if total.positive?
    end

    private

    def escrever(texto)
      Rails.logger.info("[#{nome}] #{texto}")
      puts texto
      File.open(@caminho, 'a') { |f| f.puts("#{Time.current.iso8601} #{texto}") }
    end
  end
end
