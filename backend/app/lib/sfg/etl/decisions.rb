# frozen_string_literal: true

module Sfg
  module Etl
    # As decisões que **autorizam** o ETL a prosseguir com contagem maior que zero.
    #
    # Regra da fatia, sem exceção: **nenhuma correção de dado do cliente sem decisão
    # registrada e assinada**. Anomalia vira linha de relatório, nunca `UPDATE`
    # silencioso. E anomalia sem decisão **aborta** (tarefa 5.4).
    #
    # O arquivo é versionado (`db/etl/decisions.yml`) porque a autorização precisa
    # aparecer no diff e ter autor. Uma variável de ambiente `--force` faria a mesma
    # coisa sem deixar rastro — que é exatamente o que não se quer numa migração de
    # documento financeiro.
    class Decisions
      PATH = 'db/etl/decisions.yml'

      # `expected_delta` é OPCIONAL e só existe nas chaves `discard:<tabela>`: é
      # quantas linhas a decisão autoriza a **faltar** no destino, com sinal
      # (`-2`). A reconciliação (portão 3) só considera a diferença explicada
      # quando ela bate **exatamente** com este número.
      #
      # O número é o ponto. "Esta tabela tem descarte autorizado" explicaria
      # qualquer buraco que aparecesse depois, inclusive um regressivo — a
      # autorização viraria um cheque em branco por tabela. Com a contagem
      # assinada, descartar 2 é decisão cumprida e descartar 3 volta a ser
      # bloqueio.
      Entry = Struct.new(:key, :decision, :effect, :signed_by, :at, :expected_delta,
                         keyword_init: true)

      def self.load(path = nil)
        file = Pathname.new(path || Rails.root.join(PATH))
        return new([]) unless file.exist?

        raw = YAML.safe_load_file(file, permitted_classes: [Date, Time]) || {}
        new(Array(raw['decisions']).map { |d| Entry.new(**d.symbolize_keys) })
      end

      def initialize(entries) = @entries = entries

      attr_reader :entries

      # A chave aceita `*` no fim, para autorizar uma FAMÍLIA inteira (ex.:
      # `timestamps:*`). Curinga só onde a decisão é genuinamente de classe — DEC-06
      # decide TODA hora ambígua, não uma coluna. Para órfão e duplicata o curinga é
      # errado por natureza: cada coluna é uma decisão própria, e a lista de
      # `decisions.yml` diz isso explicitamente.
      def for(key)
        entries.find { |e| e.key == key } ||
          entries.find { |e| e.key.to_s.end_with?('*') && key.to_s.start_with?(e.key.to_s.chomp('*')) }
      end

      def registered?(key) = !self.for(key).nil?

      def describe(key)
        entry = self.for(key)
        return nil if entry.nil?

        "decisão registrada: #{entry.decision} (#{entry.effect}) — assinada por #{entry.signed_by} em #{entry.at}"
      end
    end
  end
end
