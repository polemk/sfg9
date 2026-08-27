# frozen_string_literal: true

# S5 / DB-231, DB-573 — **posições diárias de risco** (`RiskEntry`).
#
# **DEC-57: tabela e model, SEM tela.** O dado sobrevive; a superfície não volta.
# É o que o legado faz hoje, e não por acidente:
#
# - não existe `app/views/pub/risk_entries` nem `.../parts/risk_entries`;
# - o controller aponta para templates inexistentes
#   (`risk_entries_controller.rb:6,29,39,47,56` → `MissingTemplate` → 500);
# - as rotas seguem no ar (`config/routes.rb:163-164`);
# - a aba está comentada (`risk/_body.html.erb:30`) e o botão "Cadastrar posição"
#   nasce com classe `deactive` (`:22-25`) — é o `drop` de **FE-234**.
#
# **O agravante que impede portar a tela mesmo se quiséssemos:** os 15 campos de
# valor são **hardcode dos 4 tipos originais** (`20210510211736_create_risk_entries.rb`)
# e **não acompanham o `RiskOperationType` dinâmico** que existe desde 2022. A
# tela portada como está não funcionaria com os tipos atuais — remodelá-la por
# tipo é feature nova, e não é desta fatia.
#
# ### Por que os nomes de coluna do domínio ficam como no legado
#
# `vencidos_value`, `a_vencer_value`, `liquidacao_value`, `descontos_value`,
# `total_carteira_value`, `total_reducoes_value` e os três blocos
# `fomento_*`/`comissaria_*`/`intercompany_*` são **substantivos do domínio** —
# os três últimos são literalmente os títulos dos tipos semeados. Esta tabela não
# tem endpoint, não tem tela e existe para que o ETL faça cópia 1:1; traduzir os
# nomes aqui só acrescentaria risco de mapeamento, sem nenhum leitor a ganhar
# legibilidade. O que **foi** alinhado ao resto do bloco é o genérico:
# `observacoes` → `observation`, igual a `risk_operations` e `risk_movements`.
#
# Integridade que o legado não tinha: único (`date`, `risk_control_id`,
# `company_id`) — era só `validates_uniqueness_of` — e FKs reais.
class PosicoesDiariasDeRisco < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_entries, id: :uuid, default: -> { 'gen_random_uuid()' },
                                comment: 'Posição diária de risco. DEC-57 — dado preservado, SEM endpoint e SEM tela.' do |t|
      t.uuid :project_id, null: false
      t.uuid :company_id, null: false
      t.uuid :risk_control_id, null: false
      t.date :date, null: false

      t.string :risk_control_title, comment: 'Cópia do título do limite no momento do lançamento.'

      t.decimal :vencidos_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :a_vencer_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :total_carteira_value, precision: 14, scale: 2, null: false, default: 0,
                                       comment: 'DERIVADO: vencidos + a_vencer. Sobrepõe qualquer valor enviado.'
      t.decimal :liquidacao_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :descontos_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :total_reducoes_value, precision: 14, scale: 2, null: false, default: 0,
                                       comment: 'DERIVADO: liquidacao + descontos.'

      t.decimal :fomento_vencidos_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :fomento_a_vencer_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :fomento_total_value, precision: 14, scale: 2, null: false, default: 0,
                                      comment: 'DERIVADO: fomento_vencidos + fomento_a_vencer.'

      t.decimal :comissaria_vencidos_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :comissaria_a_vencer_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :comissaria_total_value, precision: 14, scale: 2, null: false, default: 0,
                                         comment: 'DERIVADO: comissaria_vencidos + comissaria_a_vencer.'

      t.decimal :intercompany_vencidos_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :intercompany_a_vencer_value, precision: 14, scale: 2, null: false, default: 0
      t.decimal :intercompany_total_value, precision: 14, scale: 2, null: false, default: 0,
                                           comment: 'DERIVADO: intercompany_vencidos + intercompany_a_vencer.'

      t.string :observation, comment: 'Era `observacoes` no legado — alinhado ao resto do bloco de risco.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :risk_entries, %i[date risk_control_id company_id], unique: true,
                                                                  name: 'index_risk_entries_on_date_control_company'
    add_index :risk_entries, :risk_control_id
    add_index :risk_entries, %i[project_id date]
    add_index :risk_entries, :legacy_id, unique: true

    add_foreign_key :risk_entries, :projects, column: :project_id
    add_foreign_key :risk_entries, :companies, column: :company_id
    add_foreign_key :risk_entries, :risk_controls, column: :risk_control_id
  end
end
