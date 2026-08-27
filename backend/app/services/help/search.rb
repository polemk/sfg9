# frozen_string_literal: true

module Help
  # S12 / BE-350, BE-351, BE-362 — **a busca da ajuda**, uma só, usada pelo FAQ
  # e pela central administrativa.
  #
  # Quatro defeitos do legado (`help_items_controller.rb:9-26,28-37`) morrem
  # aqui:
  #
  #  1. **A busca não achava conteúdo novo (D-58).** O `WHERE` olhava
  #     `help_items.description` — a coluna. Desde 04/2019 o conteúdo vive em
  #     `action_text_rich_texts`, e `has_rich_text` sobrescreve o leitor da
  #     coluna. Resultado: nada criado depois de 04/2019 era encontrado, e a tela
  #     não dava nenhum sinal disso. Aqui a busca é sobre o **corpo rich text**.
  #  2. **O termo `0` casava a base inteira.** O `OR help_items.id = ?` recebia
  #     `@query.to_i`, e `"abc".to_i` é `0`. Aqui **não existe** busca por id
  #     misturada ao texto: são parâmetros distintos, declarados no Grape.
  #  3. **Sem `ORDER BY`.** A mesma busca devolvia ordens diferentes entre
  #     requisições, e a paginação repetia e pulava itens. Ordem estável aqui.
  #  4. **Sem contagem total** (BE-351). O front pedia `l = 30` ignorando o
  #     default 20 do servidor: **qualquer instalação com mais de 30 itens
  #     perdia itens em silêncio na tela**, porque não havia como saber que
  #     havia mais.
  #
  # **`ILIKE unaccent`, não `pg_search`** (design.md §3.2 / Princípio 6b):
  # `pg_search` seria o primeiro uso na base e é dependência nova. `unaccent` é
  # extensão do banco e entra por migration própria.
  module Search
    # As tags do HTML são apagadas ANTES da comparação. Sem isto, buscar por
    # "div" ou por "href" casaria praticamente todo item — o corpo é HTML.
    BODY_EXPR = "regexp_replace(action_text_rich_texts.body, '<[^>]*>', ' ', 'g')"

    module_function

    # Base comum: itens com o corpo já carregado no JOIN.
    def scope
      HelpItem.with_body
    end

    def apply_term(relation, term)
      termo = term.to_s.strip
      return relation if termo.blank?

      padrao = "%#{termo}%"
      relation.where(
        ActiveRecord::Base.sanitize_sql_array(
          ["unaccent(help_items.title) ILIKE unaccent(?) OR unaccent(#{BODY_EXPR}) ILIKE unaccent(?)",
           padrao, padrao]
        )
      )
    end

    # FAQ: busca **dentro de uma categoria**. Categoria ausente é erro de
    # parâmetro no endpoint, não lista vazia silenciosa — no legado
    # `where(help_category_id: nil)` devolvia zero itens e a tela dizia
    # "nenhum resultado", que é uma mentira sobre o acervo.
    def in_category(category, term: nil)
      apply_term(scope.where(help_category_id: category.id), term)
        .ordered
    end

    # Central administrativa: todos os grupos e categorias.
    def all(term: nil)
      apply_term(scope, term)
        .joins(category: :group)
        .order('help_groups.position ASC, help_groups.title ASC, ' \
               'help_categories.position ASC, help_categories.title ASC, ' \
               'help_items.position ASC, help_items.title ASC')
    end

    # Trecho do corpo em volta do termo — o que a lista de resultados mostra.
    # Determinístico: mesmo item, mesmo termo, mesmo trecho.
    def excerpt(item, term: nil, length: 180)
      texto = item.description_text
      return texto.first(length) if term.blank?

      indice = I18n.transliterate(texto).downcase.index(I18n.transliterate(term.to_s).downcase)
      return texto.first(length) if indice.nil?

      inicio = [indice - 40, 0].max
      trecho = texto[inicio, length].to_s
      (inicio.positive? ? "…#{trecho}" : trecho) + (inicio + length < texto.length ? '…' : '')
    end
  end
end
