# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    # **Sequência, não só `Faker`.** `Faker::Internet.email` sorteia de um
    # dicionário finito e **repete**: numa suíte que cria dezenas de usuários por
    # arquivo, a colisão com o índice único de `users.email` aparece como
    # `RecordInvalid: Email já está em uso` num exemplo qualquer, sem relação com
    # o que ele testa — falha que "some quando roda de novo" e faz o portão
    # deixar de significar alguma coisa.
    #
    # Visto em 26/08/2026 (S7): `spec/requests/api/v1/receivables_spec.rb:210`
    # falhou assim numa rodada e passou na seguinte, sem nenhuma mudança de
    # código. O prefixo sequencial mantém o realismo do `Faker` e torna o
    # endereço único por construção.
    sequence(:email) { |n| "u#{n}-#{Faker::Internet.email}" }
    user_type { create(:user_type) }

    trait :with_phone do
      email { nil }
      phone { '11999999999' }
    end

    # Os papéis reusam o MESMO `user_type` quando ele já existe: `hierarchy_level`
    # é único, então dois `create(:user, :og)` no mesmo exemplo estourariam a
    # unicidade se cada um criasse o seu.
    trait :og do
      user_type { UserType.og || create(:user_type, :og) }
    end

    trait :admin do
      user_type { UserType.admin || create(:user_type, :admin) }
    end

    trait :gerente do
      user_type { UserType.gerente || create(:user_type, :gerente) }
    end

    trait :colaborador do
      user_type { UserType.colaborador || create(:user_type, :colaborador) }
    end
  end
end
