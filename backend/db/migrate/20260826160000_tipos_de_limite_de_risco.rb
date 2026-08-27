# frozen_string_literal: true

# S5 / DB-232, DB-574 — **tipos de limite** (`RiskOperationType`). Catálogo GLOBAL.
#
# As quatro "modalidades" do Safegold — Fomento, Comissária, Intercompany e Auto
# Liquidável — **não são colunas de `risk_controls`**. Foram colunas fixas até
# 2022 (`../sfg/db/migrate/20210510211438_create_risk_controls.rb`) e viraram
# **linhas desta tabela** em `20220611152145_change_risk_control_fields.rb`.
# Quem modelar as 8 colunas antigas perde o `has_pre_faturamento`, os subtipos e
# o motor de pré-faturamento inteiro (achado C-09 do mapa).
#
# **Catálogo GLOBAL, sem `project_id`** (contrato C1, regra 4): um tipo de limite
# vale para todos os projetos, e um `risk_control` de qualquer projeto aponta
# para a mesma linha. O menu esconde a tela de administração do catálogo, não o
# dado do catálogo (DEC-18.4).
#
# Três decisões de esquema:
#
# 1. **`title` e `integration_key` únicos NO BANCO.** No legado só havia
#    `validates :title, uniqueness: true` — unicidade de aplicação, que duas
#    requisições simultâneas furam. E `integration_key` não tinha unicidade
#    nenhuma, embora seja o que a resolução por chave (B-09) usa como contrato.
# 2. **Flags `integer` viram `boolean`.** No legado são `integer default: 1` e
#    lidas por `is_active = 1` em SQL literal. Aqui são boolean `NOT NULL`; a
#    conversão do ETL é `≠ 0 → true` (DB-295).
# 3. **`has_pre_faturamento` é IMUTÁVEL depois do create**, e isso é regra de
#    aplicação (`Risk::OperationTypeService`), não de esquema: mudá-la depois
#    deixaria o tipo com o número errado de subtipos e trocaria, em silêncio, o
#    bucket de limite de toda operação já gravada.
class TiposDeLimiteDeRisco < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_operation_types, id: :uuid, default: -> { 'gen_random_uuid()' },
                                        comment: 'Tipo de limite de risco (Fomento, Comissária, …). Catálogo GLOBAL — sem escopo de projeto.' do |t|
      t.string :title, null: false, comment: 'Nome do tipo. Único — é o que a tela mostra.'
      t.string :integration_key, null: false,
                                 comment: 'Chave estável derivada do título na criação e CONGELADA depois (DC-22). É CONTRATO: fomento/comissaria/intercompany/auto_liquidavel.'
      t.boolean :is_active, null: false, default: true
      t.uuid :user_id, comment: 'Autor do cadastro. Vem da SESSÃO; o do corpo é ignorado.'
      t.boolean :is_default, null: false, default: false,
                             comment: 'Linha semeada pelo sistema. Bloqueia a exclusão (before_destroy do legado).'
      t.boolean :allow_manual_operations, null: false, default: true,
                                          comment: 'Permite lançar operação de risco à mão (S7).'
      t.boolean :allow_receivable_entries, null: false, default: true,
                                           comment: 'Permite criar operação a partir do lançamento de recebível (S6).'
      t.boolean :has_pre_faturamento, null: false, default: false,
                                      comment: 'Usa operações estáticas (par pré-faturamento/antecipação). IMUTÁVEL após o create — muda o bucket de limite de toda operação.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :risk_operation_types, :title, unique: true
    add_index :risk_operation_types, :integration_key, unique: true
    add_index :risk_operation_types, :legacy_id, unique: true
    add_index :risk_operation_types, :is_active

    add_foreign_key :risk_operation_types, :users, column: :user_id
  end
end
