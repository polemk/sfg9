# frozen_string_literal: true

# S11 / DB-085, DB-120, DB-121, DB-122, DB-124, DB-128, DB-129, DB-131, DB-132, DB-134, DB-566
#
# **Padrões de disponibilidade** — a árvore de até 3 níveis que define as linhas
# do painel de disponibilidade. Uma tabela, duas classes por STI:
# `GlobalAvailabilityTemplate` (catálogo, `project_id` nulo) e
# `ProjectAvailabilityTemplate` (padrão do projeto, `project_id` obrigatório).
#
# ## A remodelagem da hierarquia (DB-085 / DB-131)
#
# O legado guardava a árvore em **nove colunas**: `numeric_first_level`,
# `numeric_second_level`, `numeric_third_level`, `max_level`, `parent_level`,
# `is_upper_level`, `position` (string), `parent_position` (string) e
# `top_parent_id` com default `0`. Consequências medidas no legado:
#
#  - **ordenação lexicográfica** — 12 irmãos ordenam `1, 10, 11, 12, 2, 3…`,
#    porque `position` é texto (`availability_template.rb`, `order(position: :asc)`);
#  - **órfãos apontando para o id 0**, porque o default `0` não é FK;
#  - o nível era derivado com ` |= ` (OR **bit a bit**): um filho de nível 2
#    herdando de 5 virava **7** (`global_availability_template.rb:52,60,61`).
#    Funcionava por acidente enquanto os valores fossem `0`/`nil`.
#
# Aqui a árvore é **três colunas**, e uma só é a chave de ordem:
#
#  - `level`     — 1, 2 ou 3, **derivado do pai** (`parent.level + 1`);
#  - `position`  — inteiro, a posição **dentro do grupo de irmãos**;
#  - `sort_key`  — a mesma posição em forma ordenável: `"0001.0002.0003"`.
#    O caminho legível ("1.2.3") é derivado dela no model, então **não existe
#    um segundo lugar onde a numeração possa divergir**.
#
# ## O que NÃO mudou, de propósito
#
# `default_position` **nasce aqui** (DEC-79, revoga a tarefa 1.14 que mandava
# não portá-la): nenhuma migration do legado a cria, mas três views a usam e o
# `availability_templates_controller.rb:22` ordena por ela. A decisão do usuário
# foi criá-la no ai9 independentemente do que exista em produção — se existir,
# o ETL a carrega; se não, nasce vazia e a ordem cai na hierarquia.
class CreateAvailabilityTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :availability_templates, id: :uuid, comment: 'Padrão de disponibilidade — a linha do painel. STI: catálogo global (project_id nulo) ou padrão de projeto.' do |t|
      t.string :type, null: false,
               comment: 'STI — GlobalAvailabilityTemplate | ProjectAvailabilityTemplate'

      # --- Escopo (contrato C1) --------------------------------------------
      # `project_id` NULO é o catálogo global, que **não** é escopado — regra
      # oposta à das entidades de projeto, e de propósito (ver GlobalCatalog).
      t.references :project, type: :uuid, null: true, foreign_key: true, index: true,
                   comment: 'Projeto dono. NULO no catálogo global — o global não é escopado (C1, regra 4).'
      t.references :global_availability_template, type: :uuid, null: true, index: true,
                   comment: 'Padrão global de origem, quando o padrão do projeto veio do catálogo.'

      # --- Hierarquia -------------------------------------------------------
      t.uuid :parent_template_id, null: true,
             comment: 'Pai imediato. FK real — no legado era inteiro sem FK e sem índice.'
      t.uuid :top_parent_id, null: true,
             comment: 'Raiz da árvore. **Sem default 0** — o default do legado gerava órfãos apontando para o id 0.'

      t.integer :level, null: false, default: 1,
                comment: 'Profundidade 1..3. Derivada do pai (parent.level + 1), nunca por OR bit a bit.'
      t.integer :position, null: false, default: 1,
                comment: 'Posição inteira dentro do grupo de irmãos. Substitui a position string do legado.'
      t.string :sort_key, null: false, default: '0001',
               comment: 'Chave de ordenação zero-padded ("0001.0002.0003"). O caminho legível 1.2.3 é derivado dela.'
      t.integer :default_position, null: true,
                comment: 'Ordem preferencial do catálogo global (DEC-79). Nenhuma migration do legado a criava; três views a usavam.'

      # --- Atributos do padrão ---------------------------------------------
      t.string :title, null: false, comment: 'Título exibido na linha do painel.'
      t.string :operation_type, null: false,
               comment: "Natureza: C (Crédito), D (Débito), S (Saldo), M (Movimentação). Conjunto FECHADO — no legado qualquer valor fora dele era tratado como crédito (DC-28)."
      t.string :deadline_type, null: false, comment: 'Prazo: CP (Curto Prazo) ou LP (Longo Prazo).'

      t.boolean :is_global, null: false, default: false,
                comment: 'Marca de origem global. Booleano de verdade — no legado era integer 0/1.'
      t.boolean :is_mandatory, null: false, default: false,
                comment: 'Obrigatório. **O valor do formulário é respeitado** — o legado fazia `is_mandatory |= 1` e todo global nascia obrigatório.'
      t.boolean :is_active, null: false, default: true, comment: 'Ativo no painel.'
      t.boolean :is_cumulative, null: false, default: true,
                comment: 'Entra na soma do nó pai. Nó não cumulativo contribui zero (availability_entry.rb:191).'
      t.boolean :is_adjusted, null: false, default: false,
                comment: 'Valor corrigido por dias úteis. Par obrigatório com availability_entries.original_value.'
      t.boolean :should_insert_on_existing_projects, null: false, default: true,
                comment: 'DB-132 — propagar para projetos existentes. No legado tinha default 1 e NUNCA era exposta: toda criação disparava job em todos os projetos.'

      # --- Bloqueio por job em andamento (DB-128) --------------------------
      t.boolean :is_locked, null: false, default: false,
                comment: 'Bloqueado por operação em segundo plano. Padrões travados no legado MIGRAM DESBLOQUEADOS (o job que travava morreu).'
      t.datetime :locked_at, comment: 'Instante do bloqueio.'
      t.string :locked_message, comment: 'Motivo do bloqueio, em pt-BR, para a tela mostrar.'
      t.uuid :locked_by_id, comment: 'Quem disparou a operação que bloqueou. O legado não guardava autor.'

      # --- Estado da tarefa em segundo plano (DB-129) ----------------------
      # `enum` string de conjunto fechado. O legado usava texto livre em pt-BR
      # ("Concluido", sem acento), guardava array Ruby numa coluna de texto e
      # tinha `job_id` como FK para `delayed_jobs` — tabela que não existe aqui.
      t.string :job_state, comment: 'pending | running | done | failed. Conjunto fechado — o legado usava texto livre em pt-BR.'
      t.integer :job_progress, comment: 'Progresso 0..100 da operação em curso.'
      t.jsonb :job_report, comment: 'Relatório estruturado da última execução (erro, contagens). O legado gravava array Ruby em coluna de texto.'

      t.uuid :user_id, comment: 'Autor do cadastro.'

      t.timestamps
    end

    # --- FKs da hierarquia, declaradas depois porque são auto-referentes ----
    add_foreign_key :availability_templates, :availability_templates,
                    column: :parent_template_id, on_delete: :nullify
    add_foreign_key :availability_templates, :availability_templates,
                    column: :top_parent_id, on_delete: :nullify
    add_foreign_key :availability_templates, :availability_templates,
                    column: :global_availability_template_id, on_delete: :nullify
    add_foreign_key :availability_templates, :users, column: :user_id, on_delete: :nullify
    add_foreign_key :availability_templates, :users, column: :locked_by_id, on_delete: :nullify

    # --- Índices (DB-120) — o legado tinha ZERO --------------------------
    add_index :availability_templates, :parent_template_id
    add_index :availability_templates, :top_parent_id
    add_index :availability_templates, %i[type project_id sort_key],
              name: 'index_availability_templates_on_tree_order'
    add_index :availability_templates, %i[project_id is_active]

    # Unicidade do título **dentro do grupo de irmãos** (DB-122). Cobre o 3º
    # nível, que o `validates_uniqueness_of :title, scope: [:numeric_first_level,
    # :numeric_second_level, :project_id]` do legado deixava de fora: dois
    # terceiros níveis com o mesmo título passavam.
    #
    # Duas variantes porque `parent_template_id` nulo (raiz) não colide com
    # nenhum outro nulo num índice único comum do Postgres.
    add_index :availability_templates, %i[project_id parent_template_id title],
              unique: true, where: 'parent_template_id IS NOT NULL',
              name: 'index_availability_templates_unique_child_title'
    add_index :availability_templates, %i[type project_id title],
              unique: true, where: 'parent_template_id IS NULL',
              name: 'index_availability_templates_unique_root_title'

    # "Um padrão de projeto por global por projeto" (DB-122).
    add_index :availability_templates, %i[project_id global_availability_template_id],
              unique: true, where: 'global_availability_template_id IS NOT NULL',
              name: 'index_availability_templates_unique_global_per_project'
  end
end
