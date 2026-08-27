# frozen_string_literal: true

# S13 / OPS-463, OPS-127, DB-460 — o estado do job passa a viver na ENTIDADE.
#
# **O que sai:** a tabela `delayed_jobs` do legado, que guardava
# `progress_stage`/`progress_current`/`progress_max` e para a qual `projects.job_id`
# era chave estrangeira. O Sidekiq **não tem registro relacional** — não existe linha
# no banco representando um job enfileirado —, então esse acoplamento não pode
# sobreviver ao porte. `delayed_jobs` entra no ledger como `dropped` e as colunas de
# progresso nascem aqui.
#
# **Por que na entidade e não só pelo socket:** o Action Cable avisa quem está com a
# tela aberta no momento. Quem chega depois — a aba que estava fechada, o F5, o outro
# operador — precisa de uma resposta para "como está agora?". Sem estado persistido,
# a única forma seria perguntar de tempos em tempos, que é o polling que o Princípio
# 10 proíbe.
#
# `Project` é a entidade certa para começar porque é a **única** do legado que tem
# `has_ongoing_job?` (tarefa 1.3 de S13 — os outros 7 widgets leem `data-ongoing` sem
# nenhum emissor do outro lado, e são bloco morto). `availability_templates` (S11)
# ganha as mesmas duas colunas quando a tabela existir: o mecanismo é o mesmo
# (`JobProgressable`), e é de propósito que ele seja um `include` e não uma cópia.
class AddJobStateToProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :job_state, :string,
               comment: 'Estado do job em curso: running/done/failed. Substitui a FK para delayed_jobs (DB-460).'
    add_column :projects, :job_progress, :integer,
               comment: 'Percentual 0..100 do job em curso. NULL = o job ainda não reportou.'

    # Índice parcial: a consulta que importa é "quais projetos têm job rodando",
    # e ela é rara e seletiva. Índice cheio numa coluna com três valores só ocupa
    # espaço.
    add_index :projects, :job_state, where: "job_state = 'running'",
                                     name: 'index_projects_on_ongoing_job'
  end
end
