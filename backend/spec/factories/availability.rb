# frozen_string_literal: true

# S11 — as factories de disponibilidade.
#
# Duas regras que valem para todas:
#
# 1. **A posição vem do `Availability::TreeService`**, nunca de um número
#    escrito à mão. Atribuir `position` na factory faria os specs de ordenação
#    passarem por um motivo diferente do que a aplicação usa — e o defeito da
#    ordenação lexicográfica (`1, 10, 11, 2`) é exatamente o tipo de coisa que
#    some quando o teste monta a árvore por fora.
# 2. **O lançamento nasce numa empresa do PRÓPRIO projeto.** Consolidação geral
#    (`company: nil`) é derivada, e criar uma à mão esconde o D-08.
FactoryBot.define do
  factory :global_availability_template, class: 'GlobalAvailabilityTemplate' do
    sequence(:title) { |n| "Padrão global #{n}" }
    operation_type { 'C' }
    deadline_type { 'CP' }
    association :author, factory: :user

    after(:build) { |t| Availability::TreeService.assign_next_position!(t) }

    trait :debito do
      operation_type { 'D' }
    end

    trait :corrigido do
      is_adjusted { true }
    end

    trait :obrigatorio do
      is_mandatory { true }
    end

    trait :nao_cumulativo do
      is_cumulative { false }
    end
  end

  factory :project_availability_template, class: 'ProjectAvailabilityTemplate' do
    project
    sequence(:title) { |n| "Padrão do projeto #{n}" }
    operation_type { 'C' }
    deadline_type { 'CP' }
    association :author, factory: :user

    after(:build) { |t| Availability::TreeService.assign_next_position!(t) }

    trait :debito do
      operation_type { 'D' }
    end

    trait :corrigido do
      is_adjusted { true }
    end

    trait :obrigatorio do
      is_mandatory { true }
    end

    trait :nao_cumulativo do
      is_cumulative { false }
    end

    trait :inativo do
      is_active { false }
    end

    trait :bloqueado do
      is_locked { true }
      locked_message { 'Operação em andamento.' }
      locked_at { Time.current }
    end
  end

  factory :availability_entry do
    project
    availability_template factory: :project_availability_template
    date { Date.new(2026, 8, 14) }
    value { 100 }

    # A empresa e o padrão têm de ser do MESMO projeto do lançamento — as duas
    # validações de escopo (C1) recusam o contrário, e é isso que se quer.
    after(:build) do |entry|
      entry.availability_template.update_columns(project_id: entry.project_id) if entry.availability_template
      entry.company ||= Company.where(project_id: entry.project_id).first ||
                        FactoryBot.create(:company, project: entry.project)
    end
  end
end
