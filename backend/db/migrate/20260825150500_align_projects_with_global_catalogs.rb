# frozen_string_literal: true

# S3 / DB-072 — **alinha `projects` aos catálogos globais que nascem nesta fatia.**
#
# ### Por que esta migration é da S3 e não da S4
#
# A **Regra de fronteira**: quem muda a forma de um contrato ajusta os dois
# lados no mesmo passo. A S0 criou `projects.segment_id` como `t.bigint`, com o
# comentário "FK LÓGICA para `segments`; a tabela nasce depois e a constraint
# real é acrescentada lá". Ao entregar `segments` com **id `uuid`** (o padrão de
# id do ai9), a coluna `bigint` do outro lado deixa de casar — é o mesmo defeito
# que derrubou o login com
# `PG::UndefinedFunction: operator does not exist: character varying = uuid`.
# Deixar para "a fatia de projeto depois" é exatamente como o login caiu.
#
# ### O que muda
#
# 1. `projects.segment_id` passa de `bigint` para `uuid`. A coluna é
#    **recriada**, não convertida: ela nunca apontou para nada — a tabela
#    `segments` não existia até agora — e converter `bigint` em `uuid` exigiria
#    inventar um mapeamento para um dado que não há. O seed de demonstração
#    religa projeto ↔ segmento por título (`Demo::Writers::Segments`).
# 2. Nasce `projects.sub_segment_id` (`uuid`), que a S0 não criou. Sem ela o
#    `link_projects!` do seed já vinha ignorando o subsegmento em silêncio.
# 3. As duas ganham **FK real e índice** — o legado tinha ZERO `add_foreign_key`
#    na base inteira, e é o que impede `segment_id` órfão.
#
# `on_delete: :restrict` é o padrão e é deliberado: excluir um segmento em uso
# tem de responder **422**, nunca apagar o vínculo do projeto (D-24).
#
# **Escrita para ser reaplicável.** Enquanto S0..S20 rodam em paralelo, a base de
# desenvolvimento é reconstruída por `db:schema:load` mais de uma vez, e isso
# carimba TODAS as versões como aplicadas — inclusive esta, cujo efeito o
# `schema.rb` daquele momento pode não conter. Cada passo pergunta antes de
# agir: reaplicar é barato, e descobrir a coluna faltando em plena S4 não é.
class AlignProjectsWithGlobalCatalogs < ActiveRecord::Migration[8.0]
  def up
    # `bigint` que sobrou de antes da conversão para uuid: a coluna nunca
    # apontou para nada (a tabela `segments` não existia), então é recriada em
    # vez de convertida.
    remove_column :projects, :segment_id if column_exists?(:projects, :segment_id, :bigint)

    unless column_exists?(:projects, :segment_id)
      add_column :projects, :segment_id, :uuid,
                 comment: 'Segmento do projeto. FK real para `segments` (catálogo GLOBAL, sem escopo).'
    end

    unless column_exists?(:projects, :sub_segment_id)
      add_column :projects, :sub_segment_id, :uuid,
                 comment: 'Subsegmento do projeto. Catálogo INDEPENDENTE de `segments` (DC-13).'
    end

    # O comentário da S0 dizia "FK LÓGICA … a constraint real é acrescentada
    # lá". Agora ela existe — e comentário que mente é pior que comentário
    # nenhum.
    change_column_comment :projects, :segment_id,
                          'Segmento do projeto. FK real para `segments` (catálogo GLOBAL, sem escopo).'

    add_index :projects, :segment_id unless index_exists?(:projects, :segment_id)
    add_index :projects, :sub_segment_id unless index_exists?(:projects, :sub_segment_id)
    add_foreign_key :projects, :segments, column: :segment_id unless foreign_key_exists?(:projects, column: :segment_id)
    unless foreign_key_exists?(:projects, column: :sub_segment_id)
      add_foreign_key :projects, :sub_segments, column: :sub_segment_id
    end
  end

  def down
    remove_foreign_key :projects, column: :sub_segment_id
    remove_foreign_key :projects, column: :segment_id
    remove_column :projects, :sub_segment_id
    remove_column :projects, :segment_id

    add_column :projects, :segment_id, :bigint,
               comment: 'FK LÓGICA para `segments`. A tabela de segmentos nasce em S1 — a constraint real é acrescentada lá.'
    add_index :projects, :segment_id
  end
end
