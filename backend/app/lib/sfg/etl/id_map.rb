# frozen_string_literal: true

module Sfg
  module Etl
    # De-para `id legado (bigint) → id ai9 (uuid)` — DB-ETL-02.
    #
    # **Esta é a peça que sustenta as três propriedades do motor:**
    #
    # * **idempotência** — `mapped?` responde antes de inserir; rodar duas vezes não duplica;
    # * **retomada** — o de-para sobrevive ao processo morto, então a 2ª execução pula o que já entrou;
    # * **religamento de FK** — `resolve` traduz a referência da origem. Uma referência
    #   sem correspondência vira **órfã contada**, nunca id inventado.
    #
    # Não mora em `app/models` de propósito: não é domínio, é infraestrutura de migração,
    # e sai do banco depois do cutover.
    class IdMap < ApplicationRecord
      self.table_name = 'etl_id_map'

      validates :source_table, :target_table, :legacy_pk, :ai9_id, presence: true

      class << self
        # Grava o vínculo. `insert_all` com `unique_by` para que dois processos
        # concorrentes não estourem — o primeiro ganha, o segundo é no-op.
        def record!(source_table:, legacy_pk:, target_table:, ai9_id:, run_id: nil)
          now = Time.current
          insert_all(
            [{ source_table: source_table.to_s, legacy_pk: legacy_pk.to_i,
               target_table: target_table.to_s, ai9_id: ai9_id, run_id: run_id,
               created_at: now, updated_at: now }],
            unique_by: 'index_etl_id_map_on_source'
          )
        end

        # Carrega o de-para inteiro de uma tabela em memória, uma vez por lote.
        # Consultar linha a linha num de-para de milhões de linhas é o que faz um
        # ETL "que roda" virar um ETL que não termina.
        def cache_for(source_table)
          where(source_table: source_table.to_s).pluck(:legacy_pk, :ai9_id).to_h
        end

        # Tradução de UMA referência. `nil` quando não há correspondência — o
        # chamador **conta como órfã**; nunca inventa.
        def resolve(source_table, legacy_pk)
          return nil if legacy_pk.nil?

          where(source_table: source_table.to_s, legacy_pk: legacy_pk.to_i).pick(:ai9_id)
        end

        def mapped?(source_table, legacy_pk)
          exists?(source_table: source_table.to_s, legacy_pk: legacy_pk.to_i)
        end
      end
    end
  end
end
