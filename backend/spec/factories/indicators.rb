# frozen_string_literal: true

# S10 — indicadores, conexões e lançamentos.
#
# ⚠ **O título sai em CAIXA ALTA sem acento**, sempre (DEC-89). Se o seu exemplo
# escreve `title: 'Margem'` e depois compara com `'Margem'`, ele falha — e é
# assim mesmo: a normalização é o comportamento, não um detalhe da factory.
FactoryBot.define do
  factory :indicator do
    sequence(:title) { |n| "INDICADOR #{n}" }
    is_active { true }

    # Indicador ESPECÍFICO de um projeto. O global é o default (`project` nulo).
    trait :specific do
      project
    end

    trait :inactive do
      is_active { false }
    end

    trait :discarded do
      discarded_at { Time.current }
    end
  end

  factory :project_indicator_connection do
    project
    indicator
  end

  factory :indicator_entry do
    project
    indicator
    year { Date.current.year }
    sequence(:month) { |n| ((n - 1) % 12) + 1 }
    value { 1_000.00 }

    # O lançamento só faz sentido se o indicador estiver conectado ao projeto —
    # é o que a grade lê e o que o serviço exige na gravação. A factory cria a
    # conexão junto, pelo mesmo motivo da `project_guarantee`: "lembrar disso"
    # é como a regra some.
    after(:build) do |entry|
      if entry.project && entry.indicator &&
         !ProjectIndicatorConnection.exists?(project_id: entry.project.id, indicator_id: entry.indicator.id)
        ProjectIndicatorConnection.create!(project: entry.project, indicator: entry.indicator)
      end
    end
  end
end
