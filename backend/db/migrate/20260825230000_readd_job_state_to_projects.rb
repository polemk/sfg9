# frozen_string_literal: true

# S13 / OPS-463, OPS-127, DB-460 — **reaplica** `job_state`/`job_progress` em `projects`.
#
# Por que existe uma segunda migration para as mesmas duas colunas: a
# `20260825220000` as criou, e logo depois a padronização de chave primária
# (`projects.id` bigint → uuid) **recriou a tabela**. As colunas foram junto, e o
# `schema.rb` foi redumpado sem elas — em silêncio, com a versão do schema já
# apontando para a migration que as tinha criado. Ou seja: a migration constava como
# executada e a coluna não existia.
#
# Isso não é reclamação da outra fatia: é o modo de falha de duas migrations
# concorrentes sobre a mesma tabela, e ele é **mudo**. Nada reprova — `zeitwerk:check`
# passa, `rspec` passa (um `scope` que cita a coluna só é avaliado quando alguém o
# chama), e o defeito só apareceria quando o primeiro job tentasse publicar progresso.
#
# `if_not_exists` de propósito: esta migration precisa ser segura em qualquer ordem
# de aplicação — banco novo criado a partir do `schema.rb` corrigido, ou banco antigo
# que ainda tenha as colunas da primeira tentativa.
#
# O conteúdo é o mesmo da `20260825220000`; ver lá o porquê de o estado do job viver
# na entidade e não numa tabela de fila.
class ReaddJobStateToProjects < ActiveRecord::Migration[8.0]
  def up
    add_column :projects, :job_state, :string, if_not_exists: true,
               comment: 'Estado do job em curso: running/done/failed. Substitui a FK para delayed_jobs (DB-460).'
    add_column :projects, :job_progress, :integer, if_not_exists: true,
               comment: 'Percentual 0..100 do job em curso. NULL = o job ainda não reportou.'

    return if index_exists?(:projects, :job_state, name: 'index_projects_on_ongoing_job')

    # Índice parcial: a consulta que importa é "quais projetos têm job rodando".
    add_index :projects, :job_state, where: "job_state = 'running'",
                                     name: 'index_projects_on_ongoing_job'
  end

  def down
    remove_index :projects, name: 'index_projects_on_ongoing_job', if_exists: true
    remove_column :projects, :job_progress, if_exists: true
    remove_column :projects, :job_state, if_exists: true
  end
end
