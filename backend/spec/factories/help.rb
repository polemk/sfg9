# frozen_string_literal: true

FactoryBot.define do
  factory :help_group do
    sequence(:title) { |n| "Grupo #{n}" }
  end

  factory :help_category do
    association :group, factory: :help_group
    sequence(:title) { |n| "Categoria #{n}" }
    # `slug` fica de fora: é o model que o gera e desambigua (DB-368). Fixá-lo
    # aqui esconderia o defeito que a coluna existe para resolver.
  end

  factory :help_item do
    association :category, factory: :help_category
    sequence(:title) { |n| "Item #{n}" }
    description { '<p>Conteúdo do item de ajuda.</p>' }
  end
end
