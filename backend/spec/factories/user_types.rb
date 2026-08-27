# frozen_string_literal: true

# Os 4 papéis do Safegold na escala do ai9 (DEC-41): **menor = mais poder**.
# `client`, `free` e `visitor` foram removidos — se um spec seu precisava deles,
# o que ele quer é `:colaborador`.
FactoryBot.define do
  factory :user_type do
    sequence(:name) { |n| "type_#{n}" }
    description { Faker::Lorem.sentence }
    sequence(:hierarchy_level) { |n| n + 10 }

    trait :og do
      name { UserType::OG }
      hierarchy_level { 1 }
    end

    trait :admin do
      name { UserType::ADMIN }
      hierarchy_level { 2 }
    end

    trait :gerente do
      name { UserType::GERENTE }
      hierarchy_level { 3 }
    end

    trait :colaborador do
      name { UserType::COLABORADOR }
      hierarchy_level { 4 }
    end
  end
end
