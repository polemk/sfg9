# frozen_string_literal: true

module Help
  # S12 / BE-357, BE-360, BE-361 — a árvore Grupo → Categoria → Item e as duas
  # exclusões em cascata.
  #
  # **A confirmação vem do servidor** (BE-357 / BE-360). No legado o único aviso
  # de perda era um texto fixo no JS: a tela dizia "os itens serão perdidos" sem
  # saber quantos, e o servidor apagava sem contar. Aqui a contagem da subárvore
  # é resposta de endpoint, e é ela que a caixa de confirmação exibe
  # ("5 categorias e 60 itens").
  #
  # ⚠️ **Perda de dado sem lixeira**: nem o legado nem o ai9 têm soft delete
  # nestas tabelas. A decisão é herdada, está escrita, e a mitigação é a
  # contagem exata antes do ato.
  module Tree
    module_function

    # A árvore inteira, com contagem de itens. Duas consultas, não N+1.
    def call
      grupos = HelpGroup.ordered.includes(categories: :items).to_a
      grupos.map do |grupo|
        {
          group: grupo,
          categories: grupo.categories.sort_by { |c| [c.position, c.title.to_s] }.map do |categoria|
            { category: categoria, items_count: categoria.items.size }
          end
        }
      end
    end

    # O que se perde ao apagar uma categoria.
    def category_impact(category)
      { categories: 0, items: category.items.count }
    end

    # O que se perde ao apagar um grupo — a cascata **dupla**.
    def group_impact(group)
      { categories: group.categories.count, items: HelpItem.where(help_category_id: group.categories.select(:id)).count }
    end

    # Exclusão **numa única transação** (BE-357 / BE-360). O `dependent: :destroy`
    # do Rails já roda dentro de uma transação, mas a chamada explícita é o que
    # garante que a contagem devolvida e o apagamento vejam o mesmo estado.
    def destroy_category!(category)
      impacto = category_impact(category)
      ActiveRecord::Base.transaction { category.destroy! }
      impacto
    end

    def destroy_group!(group)
      impacto = group_impact(group)
      ActiveRecord::Base.transaction { group.destroy! }
      impacto
    end
  end
end
