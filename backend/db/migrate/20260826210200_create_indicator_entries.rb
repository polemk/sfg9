# frozen_string_literal: true

# S10 / DB-311, DB-587 — **lançamentos mensais de indicador**.
#
# É a maior tabela da unidade (projetos × indicadores × 12 × anos) e a única com
# dado que o cliente digita célula a célula. O legado
# (`../sfg/db/migrate/20211027140815_create_indicator_entries.rb`) criou-a com
# **zero índice** e **zero FK**, e com a identidade do lançamento existindo
# apenas em `validates_uniqueness_of :month, scope: [:year, :project_id, :indicator_id]`.
#
# O que muda, e por quê:
#
# 1. **Índice ÚNICO composto** em (`project_id`, `indicator_id`, `year`, `month`).
#    A unicidade só existia na aplicação e **havia corrida**: duas abas com a
#    grade aberta gravavam duas linhas para a mesma célula, e a leitura
#    (`.where(...).first`) mostrava uma delas sem dizer que havia outra.
# 2. **Índice de leitura** em (`project_id`, `year`, `month`, `indicator_id`).
#    É o índice que a grade usa: `EntryService#grid` troca as **12 consultas por
#    indicador** do legado (uma por célula, dentro da view) por **uma** consulta
#    por período. Sem este índice a consulta única vira varredura.
# 3. **CHECK de faixa** em `month` (1..12) e em `year`. Hoje mês 13 ou ano 0
#    passam pela validação (que só exige presença) e explodem depois em
#    `Date.new(year, month)` no `entry_pseudo_date` — 500 na renderização da
#    grade, não 422 na gravação.
# 4. **`value` aceita negativos** — replicado. A máscara do legado permite o
#    sinal na primeira posição e a view pinta em vermelho quando `< 0`
#    (`indicator_entries/list/_widget.html.erb:27`). Não há CHECK de sinal.
# 5. **`created_by` / `updated_by` no lugar de `user_id`** (Q-R28). No legado
#    `user_id` é uma coluna só, vem **do formulário** e está no `permit`: dava
#    para registrar lançamento em nome de outro usuário forjando o campo
#    escondido (`_widget.html.erb:18`). Aqui os dois vêm do servidor e
#    respondem perguntas diferentes — quem lançou e quem alterou por último.
# 6. **`title`/`key`/`value_type` continuam denormalizados**, replicando o
#    legado (T-D11 / DEC-30): renomear o indicador reescreve o histórico. Ver
#    `Indicator#propagate_denormalized_fields`.
#
# `value` fica em `decimal(15,2)` — a precisão do legado. A S4 padronizou dinheiro
# em `decimal(14,2)`, mas aqui o número não é dinheiro do borderô: é o valor que o
# cliente digita para um indicador qualquer, e reduzir a precisão poderia truncar
# um lançamento migrado. Preservar é o comportamento conservador (DEC-30).
class CreateIndicatorEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :indicator_entries, id: :uuid, default: -> { 'gen_random_uuid()' },
                                     comment: 'Lançamento mensal de um indicador num projeto. Identidade: (projeto, indicador, ano, mês).' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto dono. Obrigatório (C1).'
      t.uuid :indicator_id, null: false, comment: 'Indicador lançado.'
      t.integer :year, null: false, comment: 'Ano do lançamento. Inteiro, não data (BE-329) — a periodicidade é SEMPRE mensal.'
      t.integer :month, null: false, comment: 'Mês do lançamento, 1..12. CHECK no banco.'
      t.decimal :value, precision: 15, scale: 2, null: false, default: 0.0,
                        comment: 'Valor lançado. Zero é válido; NULL não é. ACEITA NEGATIVOS (replicado).'
      t.string :title, null: false,
                       comment: 'Foto do título do indicador no momento — reescrita quando o indicador é renomeado (T-D11).'
      t.string :key, comment: 'Foto da chave do indicador. Sem validação de presença, como no legado.'
      t.string :value_type, null: false, comment: 'Foto do tipo de valor do indicador.'
      t.uuid :created_by, comment: 'Quem lançou. Vem da SESSÃO — o `user_id` do corpo é ignorado (corrige BE-326).'
      t.uuid :updated_by, comment: 'Quem alterou por último. Vem da SESSÃO.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :indicator_entries, %i[project_id indicator_id year month], unique: true,
                                                                          name: 'index_indicator_entries_identity'
    add_index :indicator_entries, %i[project_id year month indicator_id],
              name: 'index_indicator_entries_on_grid'
    add_index :indicator_entries, :indicator_id
    add_index :indicator_entries, :legacy_id, unique: true

    add_foreign_key :indicator_entries, :projects, column: :project_id, on_delete: :cascade
    # `NO ACTION`: o lançamento é dado financeiro e não some porque alguém
    # apagou o cadastro. É o par no banco do fim do `dependent: :delete_all`.
    add_foreign_key :indicator_entries, :indicators, column: :indicator_id
    add_foreign_key :indicator_entries, :users, column: :created_by, on_delete: :nullify
    add_foreign_key :indicator_entries, :users, column: :updated_by, on_delete: :nullify

    add_check_constraint :indicator_entries, 'month BETWEEN 1 AND 12', name: 'chk_indicator_entries_month_range'
    add_check_constraint :indicator_entries, 'year BETWEEN 1900 AND 2999', name: 'chk_indicator_entries_year_range'
  end
end
