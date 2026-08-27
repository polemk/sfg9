# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `help_categories` (legado) -> `HelpCategory` (ai9). **S12** (DB-589, DB-368).
      #
      # Segundo nível da árvore de ajuda: 7 linhas em produção, medidas no dump
      # de 31/05/2025, distribuídas em 4 dos 5 grupos.
      #
      # ## O `slug` é COLUNA NOVA — e é a correção de um deep-link quebrado (DB-368)
      #
      # No legado `normalized_title` era **calculado em runtime**
      # (`../sfg/app/models/help_category.rb:8-10`) e usado como slug de
      # navegação. Duas consequências, as duas visíveis neste dump:
      #
      # 1. **renomear uma categoria quebrava o link dela**, porque o slug era o
      #    título; e
      # 2. **duas categorias cujos títulos transliteram igual produziam o MESMO
      #    slug.** Medido: dos 7 títulos saem **5 slugs distintos** — há **dois
      #    pares** de categorias homônimas, cada par em grupos diferentes. No
      #    legado, o deep-link de uma servia a outra e ninguém tinha como saber
      #    qual abriria.
      #
      # No ai9 o slug é persistido, **único no banco** (globalmente, não por
      # grupo) e não muda ao renomear — que é o ponto inteiro de um deep-link.
      #
      # **O conversor NÃO calcula o slug**, de propósito: quem calcula é
      # `HelpCategory#assign_slug`, que desambigua com sufixo numérico
      # determinístico (`conceitos`, `conceitos-2`) em vez de `SecureRandom`. E
      # como **o motor lê a origem ordenada pela PK**, quem chega primeiro fica
      # com o slug limpo, sempre a mesma linha, em toda execução. Duplicar essa
      # regra aqui criaria dois lugares que precisam concordar para sempre.
      #
      # Isso **não é anomalia e não pede decisão**: nada do cliente é alterado. O
      # legado nunca teve slug persistido, então não há link publicado que este
      # valor quebre — o que havia era a ambiguidade, que é justamente o que
      # sai. Fica registrado aqui porque um par de categorias vai nascer com
      # sufixo, e quem vir isso depois merece saber que foi de propósito.
      #
      # ## `position` — mesma história de `HelpGroups`
      #
      # Coluna nova, sem valor na origem, atribuída pelo model na criação, agora
      # **dentro do grupo** (`max` filtrado por `help_group_id`). Declarada em
      # `derived`.
      #
      # ## Integridade medida
      #
      # 0 categoria sem grupo, 0 grupo órfão e 0 duplicata em
      # `(help_group_id, title)` — a unicidade que o legado só validava em
      # aplicação (`validates_uniqueness_of :title, scope: [:help_group_id]`).
      class HelpCategories < Base
        def self.source_table = 'help_categories'
        def self.target_model = 'HelpCategory'
        def self.requires = %w[HelpCategory HelpGroup]
        def self.owner_slice = 'S12'
        def self.references = { 'help_group_id' => 'help_groups' }
        def self.uniques = [%w[help_group_id title]]
        # As duas são do ai9 e nascem no model, na criação — ver os blocos acima.
        def self.derived = %w[slug position]

        def convert(row)
          {
            help_group_id: ref('help_groups', row['help_group_id']),
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
