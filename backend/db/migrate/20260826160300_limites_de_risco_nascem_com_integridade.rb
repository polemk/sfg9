# frozen_string_literal: true

# S5 / DB-230, DB-238, DB-572 — **limites de risco** (`RiskControl`).
#
# É o teto que autoriza toda operação de crédito do Safegold: nenhuma operação
# de risco e nenhum recebível existem sem um limite cadastrado para a combinação
# (empresa, portador, tipo).
#
# ### A forma correta é a PÓS-2022 (achado C-09), verificada na fonte
#
# | Migration legada | O que faz |
# | ---------------- | --------- |
# | `20210510211438_create_risk_controls.rb` | 8 colunas fixas `limite_*`/`taxa_*` (auto_liquidaveis, fomento, comissaria, intercompany) |
# | `20220611152145_change_risk_control_fields.rb` | acrescenta `risk_operation_type_id`, `user_id`, `limite`, `taxa`, `original_balance`, `original_balance_pre` |
#
# Ou seja: **hoje é uma linha por (empresa, portador, tipo)**, com UM `limite` e
# UMA `taxa`. As 4 modalidades são linhas de `risk_operation_types`.
#
# ### As 8 colunas pré-2022 nascem PRESERVADAS (DEC-43)
#
# O descarte é adiado para o ETL (S14) e depende de uma contagem no dump de
# produção — `SELECT count(*) FROM risk_controls WHERE risk_operation_type_id IS NULL`
# —, que **o orquestrador não tem**. Preservar coluna vazia é barato; descartar
# coluna com dado é irreversível. Enquanto a contagem não vier, o rótulo
# "Legado" da tela (FE-243) fica de pé.
#
# ### Nenhuma das 7 tabelas de risco do legado declara um único índice ou FK
#
# Aqui todas nascem com integridade (DB-238):
#
# - **único (`company_id`, `carrier_id`, `risk_operation_type_id`)** — no legado
#   era só `validates_uniqueness_of`, unicidade de aplicação que duas requisições
#   simultâneas furam. Dois limites para a mesma combinação **dobram a exposição
#   exibida**, porque o agregado soma limite por limite;
# - **(`project_id`, `is_active`)** — é exatamente o filtro de todo agregado
#   (`active_risk_controls`);
# - FKs reais, todas `NO ACTION`: excluir portador com limite **bloqueia**. No
#   legado `Carrier has_many :risk_controls, dependent: :destroy` — excluir um
#   portador **apagava os limites dele** (D-24, a assimetria mais perigosa do
#   bloco).
#
# **`has_safegold_management` NÃO vira coluna**, para bater com a escolha da S4
# em `Company`: lá a marca é derivada do projeto na leitura e não há coluna para
# divergir (`app/models/company.rb`). O legado carimbava a cópia em
# `before_validation` e re-carimbava com `update_all` — histórico inconsistente
# por design (D-30/DC-01). O valor lido é o mesmo; o que não existe é a segunda
# fonte de verdade.
class LimitesDeRiscoNascemComIntegridade < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_controls, id: :uuid, default: -> { 'gen_random_uuid()' },
                                 comment: 'Limite de risco: o teto de (empresa × portador × tipo). Escopado por projeto — contrato C1.' do |t|
      t.uuid :project_id, null: false, comment: 'Derivado de company.project_id no before_validation. O do corpo é ignorado.'
      t.uuid :company_id, null: false
      t.uuid :carrier_id, null: false
      t.uuid :risk_operation_type_id, null: false
      t.uuid :user_id, comment: 'Autor. Vem da SESSÃO.'

      t.string :title, comment: 'Cópia do título do portador, reescrita em TODO save. É por ela que a lista ordena.'

      t.decimal :limite, precision: 14, scale: 2, null: false, default: 0,
                         comment: 'O teto. Zero continua válido — é o que mantém vivo o ramo de divisão protegida do agregado.'
      t.decimal :taxa, precision: 7, scale: 4, null: false, default: 0, comment: 'Taxa acordada do limite, em % a.m.'

      t.decimal :original_balance, precision: 14, scale: 2, null: false, default: 0,
                                   comment: 'Saldo inicial LIQUIDÁVEL. Vira a operação estática de antecipação (BE-241).'
      t.decimal :original_balance_pre, precision: 14, scale: 2, null: false, default: 0,
                                       comment: 'Saldo inicial PRÉ. Vira a operação estática de pré-faturamento (BE-241).'

      t.boolean :is_active, null: false, default: true,
                            comment: 'Limite desativado some do resumo do console E continua listando suas operações (decisão B-02, duas leituras divergentes REPLICADAS).'

      # --- As 8 colunas pré-2022 (DEC-43) ---------------------------------
      # Preservadas até a contagem no dump. Nenhum código do ai9 as lê: o motor
      # de exposição usa `limite`/`taxa` e o tipo. Elas existem só para que o
      # ETL não perca dado que talvez exista.
      t.decimal :limite_auto_liquidaveis, precision: 15, scale: 2, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL. Não é lida por nada no ai9.'
      t.float :taxa_auto_liquidaveis, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL.'
      t.decimal :limite_fomento, precision: 15, scale: 2, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL.'
      t.float :taxa_fomento, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL.'
      t.decimal :limite_comissaria, precision: 15, scale: 2, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL.'
      t.float :taxa_comissaria, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL.'
      t.decimal :limite_intercompany, precision: 15, scale: 2, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL.'
      t.float :taxa_intercompany, default: 0, comment: 'DEC-43 — coluna pré-2022, preservada para o ETL.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :risk_controls, %i[company_id carrier_id risk_operation_type_id], unique: true,
                                                                                name: 'index_risk_controls_on_company_carrier_type'
    add_index :risk_controls, %i[project_id is_active]
    add_index :risk_controls, :carrier_id
    add_index :risk_controls, :risk_operation_type_id
    add_index :risk_controls, :title
    add_index :risk_controls, :legacy_id, unique: true

    add_foreign_key :risk_controls, :projects, column: :project_id
    add_foreign_key :risk_controls, :companies, column: :company_id
    add_foreign_key :risk_controls, :carriers, column: :carrier_id
    add_foreign_key :risk_controls, :risk_operation_types, column: :risk_operation_type_id
    add_foreign_key :risk_controls, :users, column: :user_id
  end
end
