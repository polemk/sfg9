# frozen_string_literal: true

# S10 / DB-312, DB-586 — **fecha a conexão projeto ↔ indicador**.
#
# A tabela em si já existe: a **S4** a criou em
# `20260826100300_create_project_connections.rb:52`, com os dois `uuid`, os
# índices e o único composto (`project_id`, `indicator_id`), e deixou escrito no
# comentário da coluna que **a FK para `indicators` é da S10** — porque quando
# aquela migration rodou a tabela `indicators` ainda não existia. Esta migration
# é a outra metade desse combinado; ela **não recria** a tabela (recriar
# derrubaria em silêncio o que outra fatia acrescentar depois).
#
# O que falta e entra aqui:
#
# 1. **A FK real para `indicators`**, em `NO ACTION`. É ela que impede apagar de
#    verdade um indicador que algum projeto ainda usa — o par no banco do
#    `restrict_with_error` do model. O caminho normal de exclusão é lógico
#    (`indicators.discarded_at`, D-66) e a purga só alcança quem não tem vínculo.
# 2. **`legacy_id`**, para o ETL da S14 poder reconciliar as conexões do legado
#    (DEC-12), no mesmo formato das outras tabelas desta migração.
#
# **A coluna `is_active` continua não existindo, de propósito.** O
# `project_indicator_connections_controller.rb:192-198` do legado a aceita no
# `permit` e ela **não existe na tabela** — o parâmetro é descartado em silêncio
# desde 2021. Criá-la seria materializar um campo que nunca teve leitor.
class CreateProjectIndicatorConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :project_indicator_connections, :legacy_id, :integer,
               comment: 'DEC-12 — proveniência do registro na base do legado.'
    add_index :project_indicator_connections, :legacy_id, unique: true

    add_foreign_key :project_indicator_connections, :indicators, column: :indicator_id
  end
end
