# frozen_string_literal: true

module Seeds
  module Reference
    # S3 / **OPS-540** — o relatório de um catálogo de referência.
    #
    # Existe para que "rodei o seed" seja uma frase com número: quantas linhas
    # nasceram, quantas foram atualizadas e quantas já estavam certas. Sem isso,
    # "idempotente" é promessa; com isso, a segunda execução **mostra** zero
    # criados e zero atualizados, e o teste de idempotência (F.5) tem o que
    # comparar.
    class Report
      attr_reader :catalog, :created, :updated, :unchanged, :skipped_message

      def initialize(catalog:, created: 0, updated: 0, unchanged: 0, skipped_message: nil)
        @catalog = catalog
        @created = created
        @updated = updated
        @unchanged = unchanged
        @skipped_message = skipped_message
      end

      def self.skipped(catalog, message)
        new(catalog: catalog, skipped_message: message)
      end

      def skipped? = skipped_message.present?
      def total = created + updated + unchanged
      def idempotent? = created.zero? && updated.zero?

      def to_s
        return "⏭ #{catalog} — #{skipped_message}" if skipped?

        format('✔ %-38<c>s %<cr>3d criados · %<up>3d atualizados · %<un>3d inalterados',
               c: catalog, cr: created, up: updated, un: unchanged)
      end
    end
  end
end
