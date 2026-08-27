# frozen_string_literal: true

# S4 / **DB-092** — `indicators.scope` explícito.
#
# Até aqui a interface inteira era governada por um campo **nulo**:
# `project_id IS NULL` significava "global" no model (`Indicator#global?`), na
# entity (`scope` derivado), no serviço de conexões (`available_for`) e na tela
# (`indicador.scope === 'global'`). O front **já mandava** `scope: 'project'` na
# criação e **já lia** `scope` na linha — só que do lado do banco esse conceito
# não existia: era inferido a cada leitura.
#
# Inferir escopo de um campo nulo tem três custos concretos:
#
# 1. **Não dá para restringir no banco.** Nada impedia um `UPDATE` que zerasse
#    `project_id` de um específico e o promovesse a global em silêncio — sem
#    passar por validação, sem auditoria, e levando junto o histórico.
# 2. **Índice parcial em `NULL`.** Filtrar "só os globais" é `WHERE project_id
#    IS NULL`; com a coluna, é igualdade — indexável e legível no plano.
# 3. **O contrato fica implícito para quem chega depois.** Um leitor do schema
#    tinha de saber a convenção; agora a coluna e o CHECK a dizem.
#
# O CHECK abaixo é o ponto do DB-092: as duas representações **não podem
# divergir**. Global tem `project_id` nulo; de projeto, preenchido. Não é
# denormalização opcional — é a restrição que torna a coluna confiável.
class AddScopeToIndicators < ActiveRecord::Migration[7.1]
  def up
    add_column :indicators, :scope, :string,
               comment: 'DB-092 — escopo EXPLÍCITO: `global` ou `project`. Coerente com `project_id` por CHECK.'

    # Backfill a partir do que já governava a interface. É a única leitura em
    # que `project_id IS NULL` decide o escopo — daqui em diante quem decide é
    # a coluna.
    execute(<<~SQL.squish)
      UPDATE indicators
         SET scope = CASE WHEN project_id IS NULL THEN 'global' ELSE 'project' END
    SQL

    change_column_null :indicators, :scope, false
    change_column_default :indicators, :scope, from: nil, to: 'global'

    add_check_constraint :indicators,
                         "(scope = 'global' AND project_id IS NULL) OR (scope = 'project' AND project_id IS NOT NULL)",
                         name: 'chk_indicators_scope_matches_project'

    # `(scope, title)` e não só `scope`: o filtro da tela de específicos vem
    # sempre acompanhado da ordenação por título, que é o default do
    # `Indicator::ORDERING`.
    add_index :indicators, %i[scope title], name: 'index_indicators_on_scope_and_title'
  end

  def down
    remove_index :indicators, name: 'index_indicators_on_scope_and_title'
    remove_check_constraint :indicators, name: 'chk_indicators_scope_matches_project'
    remove_column :indicators, :scope
  end
end
