# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `help_groups` (legado) -> `HelpGroup` (ai9). **S12** (DB-588, DB-367, BE-358).
      #
      # Primeiro nível da árvore de ajuda. 5 linhas em produção, medidas no dump
      # de 31/05/2025 — e são elas que ordenam o menu inteiro da central.
      #
      # ## `user_id` NÃO viaja, porque a coluna nunca existiu
      #
      # BE-358: o `permit` do `help_groups_controller.rb` do legado aceitava
      # `:user_id` numa tabela que **não tem a coluna**. Um formulário que o
      # enviasse causaria `UnknownAttributeError`. Não se porta um campo cuja
      # única possibilidade é falhar — e nem a origem tem de onde tirá-lo: as
      # colunas de `help_groups` são `id`, `title` e os dois timestamps. Só isso.
      #
      # ## `position` é COLUNA NOVA e nasce da ORDEM DE LEITURA — DB-367
      #
      # No legado a view ordenava por `title ASC`: **renomear um grupo reordenava
      # o menu inteiro**, sem ninguém pedir. No ai9 a ordem é persistida.
      #
      # A coluna não existe na origem, então não há valor a copiar — e inventar
      # um seria pior que deixar o model atribuir. `HelpGroup#assign_position`
      # (`on: :create`) dá `max + 1`, e como **o motor lê a origem ordenada pela
      # PK** (`Source::Base#each_batch`), a numeração sai estável entre execuções
      # e reproduz a ordem de criação no legado — que é a melhor aproximação
      # honesta de "a ordem que eles tinham". Declarada em `derived`: comparar
      # `position` na reconciliação acusaria divergência contra uma coluna que a
      # origem não tem.
      #
      # ## A unicidade que o legado só validava em aplicação
      #
      # `validates :title, uniqueness: true` (`../sfg/app/models/help_group.rb:6`).
      # No ai9 é índice **funcional** no banco, `lower(title)`. Medido: 5 títulos,
      # 5 distintos ignorando caixa — a produção cabe na restrição nova como está.
      class HelpGroups < Base
        def self.source_table = 'help_groups'
        def self.target_model = 'HelpGroup'
        def self.owner_slice = 'S12'
        # A origem não tem NENHUMA FK aqui: o grupo é a raiz da árvore.
        def self.references = {}
        def self.uniques = [%w[title]]
        # `position` é do ai9 e o model a atribui na criação — ver o bloco acima.
        def self.derived = %w[position]

        def convert(row)
          {
            # O model faz `strip` em todo save (`normalize_title`); fazê-lo aqui é
            # o que deixa a reconciliação comparar o valor gravado, não o cru.
            title: row['title'].to_s.strip,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end
