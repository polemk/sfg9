# frozen_string_literal: true

# S3 — os cinco catálogos GLOBAIS. Nenhum tem `project_id`: catálogo global não
# recebe escopo de projeto (contrato C1, regra 4). Se você veio acrescentar
# `project` a alguma destas factories, leia `app/models/concerns/global_catalog.rb`.
FactoryBot.define do
  factory :carrier_group do
    sequence(:title) { |n| "Grupo #{n}" }
  end

  factory :carrier do
    sequence(:title) { |n| "Portador #{n}" }
    financial_agent { 'FIDC' }

    trait :fidc do
      financial_agent { 'FIDC' }
      senior_accounts { 800 }
      subordinated_accounts { 200 }
      net_worth { 15_000_000.00 }
    end

    # `001` é o caso do DC-12: o legado guardava `integer` e o zero à esquerda
    # sumia. A factory usa o valor real do COMPE de propósito.
    trait :banco_do_brasil do
      title { 'Banco do Brasil S.A.' }
      bank_code { '001' }
    end
  end

  factory :segment do
    sequence(:title) { |n| "Segmento #{n}" }
  end

  factory :sub_segment do
    sequence(:title) { |n| "Subsegmento #{n}" }
  end

  factory :project_guarantee_type do
    sequence(:title) { |n| "Tipo de garantia #{n}" }
  end
end
