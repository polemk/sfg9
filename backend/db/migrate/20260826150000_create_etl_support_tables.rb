# frozen_string_literal: true

# S14 — as duas tabelas de apoio do ETL de produção (DB-ETL-02, tarefas 2.1 e 2.2).
#
# **Por que existem, e por que são tabelas e não memória:**
#
# `etl_id_map` é o **de-para de identidade**. O legado é `bigint` auto-incremento;
# o ai9 é `uuid` (`ai9-conventions.md` §4). Religar uma FK reaproveitando o inteiro
# da origem é o defeito que derrubou o login em 25/08/2026
# (`operator does not exist: character varying = uuid`) — e, pior, num banco em que
# os dois lados fossem inteiros, associaria o registro **errado em silêncio**.
# `legacy_id` continua na tabela de destino como **proveniência** (DEC-12/BE-451),
# nunca como chave.
#
# `etl_checkpoints` é o que torna a carga **retomável**. O checkpoint é gravado
# DENTRO da transação do lote: ou o lote inteiro entrou e o checkpoint avançou, ou
# nenhum dos dois. Matar o processo no meio deixa o banco consistente no último lote
# completo — que é o teste de 6.2.
#
# As duas são infraestrutura de migração, não domínio: não têm entidade, não têm
# endpoint e saem do banco depois do cutover (passo do runbook).
class CreateEtlSupportTables < ActiveRecord::Migration[8.0]
  def change
    create_table :etl_id_map, id: :uuid, default: -> { 'gen_random_uuid()' },
                              comment: 'De-para id legado (bigint) → id ai9 (uuid). Sustenta idempotência, retomada e religamento de FK — DB-ETL-02.' do |t|
      t.string :source_table, null: false, comment: 'Tabela na ORIGEM (nome legado, ex.: livetat_auth_users).'
      t.bigint :legacy_pk, null: false, comment: 'Chave primária na origem.'
      t.string :target_table, null: false, comment: 'Tabela no destino ai9 (ex.: users).'
      t.uuid   :ai9_id, null: false, comment: 'Id do registro gravado no ai9.'
      t.string :run_id, comment: 'Execução que gravou a linha. Diagnóstico; não entra na chave.'
      t.timestamps

      # A chave da idempotência. Linha já mapeada = pular, sem consultar o destino.
      t.index %i[source_table legacy_pk], unique: true, name: 'index_etl_id_map_on_source'
      t.index %i[target_table ai9_id], name: 'index_etl_id_map_on_target'
    end

    create_table :etl_checkpoints, id: :uuid, default: -> { 'gen_random_uuid()' },
                                   comment: 'Ponto de retomada por (execução, tabela). Gravado na MESMA transação do lote.' do |t|
      t.string  :run_id, null: false, comment: 'Identificador da execução de carga.'
      t.string  :source_table, null: false, comment: 'Tabela da origem sendo carregada.'
      t.bigint  :last_legacy_pk, comment: 'Última PK da origem confirmada. NULL = nada processado ainda.'
      t.integer :processed_count, null: false, default: 0, comment: 'Linhas lidas da origem até aqui.'
      t.integer :written_count, null: false, default: 0,
                                comment: 'Linhas gravadas no destino (exclui as puladas por já estarem no de-para).'
      t.integer :skipped_count, null: false, default: 0,
                                comment: 'Linhas puladas por já existirem no de-para. Numa 2ª execução, isto vira o total.'
      t.string  :state, null: false, default: 'pending', comment: 'pending | running | done | aborted'
      t.text    :message, comment: 'Motivo do aborto, quando houver.'
      t.datetime :started_at
      t.timestamps

      t.index %i[run_id source_table], unique: true, name: 'index_etl_checkpoints_on_run_and_table'
    end
  end
end
