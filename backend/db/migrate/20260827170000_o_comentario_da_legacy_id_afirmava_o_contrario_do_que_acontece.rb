# frozen_string_literal: true

# **D-PAR-07 — a coluna tinha dois significados, e o comentário descrevia o
# perdedor.**
#
# O comentário de `receivable_entries.legacy_id` dizia, com todas as letras, que
# ela guarda "a proveniência do ETL Django→Rails de 2021, 17.610 linhas
# preenchidas em produção". **Ela não guarda.**
#
# A origem tem as DUAS colunas — `id` (PK) e `legacy_id integer`, esta com índice
# único próprio —, e a segunda é mesmo a proveniência do Django. Mas todo
# conversor grava `legacy_id: row['id']`, e não por descuido:
# `etl/converters/base.rb:212` define `natural_key(row) = { legacy_id:
# row[legacy_pk] }`. É por essa coluna que a carga das 32 tabelas é idempotente e
# retomável — trocar o significado quebraria o `resume` inteiro.
#
# Resultado medido: depois da carga a coluna tem 28.131 ids do Rails legado, e
# não os 17.610 do Django. O conversor só LÊ a `legacy_id` da origem, e só para o
# relatório de anomalia da Q-B19 (`receivable_entries.rb:479`).
#
# Esta migration não muda dado nem comportamento: corrige o que a coluna DIZ
# sobre si mesma. Comentário que afirma o contrário do que acontece é pior do que
# nenhum — quem for procurar o borderô de 2021 por ele vai procurar em vão.
#
# **A escolha entre as duas semânticas continua em aberto** (D-PAR-07, DB-157) e
# é do Vinícius: aceitar a convenção e descartar a proveniência do Django, ou
# criar coluna separada para ela.
class OComentarioDaLegacyIdAfirmavaOContrarioDoQueAcontece < ActiveRecord::Migration[8.0]
  TEXTO = 'Id que a linha tinha no sfg legado — a convenção do motor de carga, que a usa como ' \
          'chave natural do `resume` (`etl/converters/base.rb:212`). ⚠ NÃO é a `legacy_id` da ' \
          'ORIGEM, que guardava a proveniência do ETL Django→Rails de 2021 (17.610 linhas): essa ' \
          'NÃO é migrada. Ver D-PAR-07 e DB-157.'

  ANTERIOR = 'DEC-12 — proveniência do ETL Django→Rails de 2021 ' \
             '(`receivable_entries.legacy_id`, 17.610 linhas preenchidas em produção). ' \
             'O ETL não é portado; a coluna sim (DB-157).'

  def up
    change_column_comment :receivable_entries, :legacy_id, TEXTO
  end

  def down
    change_column_comment :receivable_entries, :legacy_id, ANTERIOR
  end
end
