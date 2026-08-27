# frozen_string_literal: true

# S4 — os recursos **escopados por projeto**. Espelho deliberado de
# `spec/factories/catalogs.rb`, que é o oposto: lá nenhuma factory tem
# `project`, aqui **todas** têm. As duas regras convivem por desenho (C1).
FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "Projeto #{n}" }
    sequence(:slug) { |n| "projeto-#{n}" }
    association :owner, factory: :user
  end

  factory :company do
    project
    sequence(:title) { |n| "Empresa #{n}" }
  end

  factory :provider do
    project
    sequence(:title) { |n| "Fornecedor #{n}" }

    trait :com_cnpj do
      document_type { 'CNPJ' }
      # CNPJ com dígito verificador válido.
      document { '11222333000181' }
    end

    trait :com_cpf do
      document_type { 'CPF' }
      document { '52998224725' }
    end
  end

  factory :project_to_carrier_connection do
    project
    carrier
  end

  factory :project_guarantee do
    project
    carrier
    guarantee_type factory: :project_guarantee_type
    sequence(:title) { |n| "Garantia #{n}" }
    value { 100_000.00 }

    # A garantia só é válida com o portador CONECTADO ao projeto (BE-119). A
    # factory cria a conexão junto — senão todo exemplo teria de lembrar disso,
    # e "lembrar disso" é como a regra some.
    after(:build) do |guarantee|
      if guarantee.project && guarantee.carrier &&
         !ProjectToCarrierConnection.exists?(project_id: guarantee.project.id, carrier_id: guarantee.carrier.id)
        ProjectToCarrierConnection.create!(project: guarantee.project, carrier: guarantee.carrier)
      end
    end
  end
end
