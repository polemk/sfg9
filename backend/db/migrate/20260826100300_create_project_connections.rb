# frozen_string_literal: true

# S4 / DB-068, DB-081, DB-082, DB-554 — **as duas pontes do projeto**.
#
# `project_to_carrier_connections` é a **ÚNICA** ponte projeto↔portador (DB-068):
# os portadores de uma empresa são **derivados do projeto**
# (`Company#carriers` é `has_many through: :project`). Nenhuma tabela
# empresa↔portador é inventada — o legado não tem e a tela não precisa.
#
# Duas coisas que o legado não tinha e que entram aqui:
#
# 1. **Índice único composto.** A unicidade era só de aplicação
#    (`validates_uniqueness_of :carrier_id, scope: [:project_id]`), e duas abas
#    a furam. ⚠ **A base do legado pode já conter duplicatas** — o ETL da S14
#    tem de deduplicar antes de carregar.
# 2. **FK real.** O legado tem ZERO `add_foreign_key` na base inteira: apagar um
#    portador deixava `carrier_id` órfão apontando para nada. Aqui a FK é
#    `NO ACTION`, que é a segunda camada do bloqueio já declarado em
#    `Carrier.blocking_dependents` (D-24: no legado excluir portador APAGAVA os
#    limites de risco dele).
#
# ⚠ **`project_indicator_connections` nasce SEM a FK para `indicators`**: a
# tabela `indicators` é da **S10** e ainda não existe. O contrato está escrito
# aqui e a FK entra na migration da fatia dona, junto com `indicators.scope`
# (DB-092) — que é a coluna que substitui o `project_id IS NULL` como definição
# de "indicador global". Migration condicional esconderia a dependência.
#
# `is_active` **não existe** em `project_indicator_connections`, de propósito: o
# `permit` do controller legado o aceitava sem que a coluna existisse.
class CreateProjectConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :project_to_carrier_connections, id: :uuid, default: -> { 'gen_random_uuid()' },
                                                  comment: 'Ponte ÚNICA projeto ↔ portador (DB-068). Os portadores da empresa são derivados do projeto.' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto conectado.'
      t.uuid :carrier_id, null: false, comment: 'Portador conectado. Catálogo GLOBAL — a conexão é que é escopada.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência (`fbancoproj.bcp_id` na base de origem).'
      t.integer :legacy_project_id, comment: 'DEC-12 — `fbancoproj.pro_id`.'
      t.integer :legacy_carrier_id, comment: 'DEC-12 — `fbancoproj.bco_id`.'

      t.timestamps
    end

    add_index :project_to_carrier_connections, :project_id
    add_index :project_to_carrier_connections, :carrier_id
    add_index :project_to_carrier_connections, %i[project_id carrier_id], unique: true,
                                                                          name: 'index_ptcc_on_project_and_carrier'
    add_index :project_to_carrier_connections, :legacy_id, unique: true

    add_foreign_key :project_to_carrier_connections, :projects, column: :project_id
    add_foreign_key :project_to_carrier_connections, :carriers, column: :carrier_id

    create_table :project_indicator_connections, id: :uuid, default: -> { 'gen_random_uuid()' },
                                                 comment: 'Ponte projeto ↔ indicador. A FK para `indicators` é acrescentada pela S10, dona da tabela.' do |t|
      t.uuid :project_id, null: false, comment: 'Projeto conectado.'
      t.uuid :indicator_id, null: false,
                            comment: 'Indicador conectado. FK acrescentada pela S10 junto com `indicators.scope` (DB-092).'

      t.timestamps
    end

    add_index :project_indicator_connections, :project_id
    add_index :project_indicator_connections, :indicator_id
    add_index :project_indicator_connections, %i[project_id indicator_id], unique: true,
                                                                          name: 'index_pic_on_project_and_indicator'

    add_foreign_key :project_indicator_connections, :projects, column: :project_id
  end
end
