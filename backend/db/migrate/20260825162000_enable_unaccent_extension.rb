# frozen_string_literal: true

# S12 / BE-350 — habilita a extensão `unaccent` do PostgreSQL.
#
# A busca da central de ajuda e do FAQ é `ILIKE unaccent` sobre
# `action_text_rich_texts.body` (design.md §3.2). A decisão de NÃO estrear o
# `pg_search` foi tomada por proporcionalidade (Princípio 6b) — mas `unaccent`
# não é dependência nova de aplicação: é extensão do banco, e sem ela a busca
# por "duvida" não acha "dúvida", que é o defeito que a decisão existe para
# resolver.
#
# O `schema.rb` da base só declarava `plpgsql` e `pgcrypto`; esta migration é o
# que faz a terceira aparecer lá. Sem ela, `rails db:schema:load` monta um banco
# em que TODA busca de ajuda levanta `PG::UndefinedFunction` — e o erro só
# aparece na primeira busca, não no boot.
class EnableUnaccentExtension < ActiveRecord::Migration[8.0]
  def up
    enable_extension 'unaccent'
  end

  def down
    disable_extension 'unaccent'
  end
end
