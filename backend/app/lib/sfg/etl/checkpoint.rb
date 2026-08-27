# frozen_string_literal: true

module Sfg
  module Etl
    # Ponto de retomada por (execução, tabela) — tarefa 2.2.
    #
    # **Regra que não pode ser afrouxada:** o checkpoint é gravado dentro da MESMA
    # transação do lote. Gravar depois abre a janela em que o lote entrou e o
    # checkpoint não avançou — e a retomada reprocessa o lote. Com o de-para isso
    # não duplicaria, mas mascararia o defeito; com uma tabela sem de-para,
    # duplicaria.
    class Checkpoint < ApplicationRecord
      self.table_name = 'etl_checkpoints'

      STATES = %w[pending running done aborted].freeze

      validates :run_id, :source_table, presence: true
      validates :state, inclusion: { in: STATES }

      def self.for(run_id:, source_table:)
        find_or_create_by!(run_id: run_id, source_table: source_table.to_s) do |record|
          record.state = 'pending'
          record.started_at = Time.current
        end
      end

      # Avança dentro da transação do lote.
      def advance!(last_pk:, processed:, written:, skipped:)
        update!(last_legacy_pk: last_pk,
                processed_count: processed_count + processed,
                written_count: written_count + written,
                skipped_count: skipped_count + skipped,
                state: 'running')
      end

      def finish! = update!(state: 'done')
      def abort!(message) = update!(state: 'aborted', message: message)
      def resumable? = state == 'running'
    end
  end
end
