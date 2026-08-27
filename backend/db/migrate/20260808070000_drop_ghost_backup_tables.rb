# frozen_string_literal: true

# Derruba as duas tabelas de backup de 31/05.
#
# `chat_sessions_ghost_bkp_20260531` (4.893 linhas) e
# `flow_executions_ghost_bkp_20260531` (5.106) foram cópias tiradas à mão
# naquele dia e nunca mais tocadas: a linha mais nova de cada uma é do próprio
# 31/05. Nenhum arquivo do app as menciona e nenhuma chave estrangeira aponta
# para elas — verificado no catálogo antes de escrever esta migration.
#
# Depois do reset de captação elas viraram a única coisa apontando para ids de
# lead e de sessão que não existem mais, e ficariam eternamente como "3 MB de
# ponteiro para o vazio" atrapalhando qualquer auditoria futura de integridade.
#
# Um dump completo foi tirado antes (pg_dump das duas tabelas, 2,7 MB) —
# `down` recria a estrutura, mas o CONTEÚDO só volta por esse arquivo. Por isso
# o irreversível está dito aqui em vez de fingir que não é.
class DropGhostBackupTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :chat_sessions_ghost_bkp_20260531, if_exists: true
    drop_table :flow_executions_ghost_bkp_20260531, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Restaure de /tmp/ghost_bkp_20260531.sql (pg_dump tirado em 08/08/2026 antes do drop).'
  end
end
