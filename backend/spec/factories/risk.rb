# frozen_string_literal: true

# S5 — as factories do bloco de risco.
#
# Duas regras que valem para todas elas:
#
# 1. **O tipo gera os próprios subtipos** no `after_create`. Nenhuma factory
#    cria subtipo à mão — fazer isso furaria o índice único
#    (`risk_operation_type_id`, `is_pre`) e esconderia o dia em que o
#    `after_create` parasse de rodar.
# 2. **O limite abre o par estático** quando o tipo usa pré-faturamento. Um
#    `create(:risk_control, risk_operation_type: tipo_com_pre)` já vem com duas
#    `RiskOperation` penduradas — e é isso que faz `available_for_entry_on`
#    nunca listá-lo. Não é efeito colateral da factory: é o comportamento.
FactoryBot.define do
  factory :risk_operation_type do
    sequence(:title) { |n| "Tipo de limite #{n}" }
    has_pre_faturamento { false }

    trait :com_pre do
      has_pre_faturamento { true }
    end

    trait :semeado do
      is_default { true }
    end
  end

  factory :risk_movement_type do
    sequence(:title) { |n| "Movimento #{n}" }
    credit_type { 'D' }

    trait :credito do
      credit_type { 'C' }
    end

    trait :debito do
      credit_type { 'D' }
    end

    trait :semeado do
      is_default { true }
    end
  end

  factory :risk_control do
    project
    company { association :company, project: project }
    carrier
    risk_operation_type
    limite { 200_000.00 }
    taxa { 2.55 }
    original_balance { 0 }
    original_balance_pre { 0 }

    # O portador precisa estar conectado ao projeto — é o mesmo critério que o
    # servidor aplica no `create` (C1).
    after(:build) do |control|
      if control.project && control.carrier &&
         !ProjectToCarrierConnection.exists?(project_id: control.project.id, carrier_id: control.carrier.id)
        ProjectToCarrierConnection.create!(project: control.project, carrier: control.carrier)
      end
    end
  end

  factory :risk_operation do
    # **S7** — `user_id` é `validates presence` no legado
    # (`../sfg/app/models/risk_operation.rb:58`) e a S7 trouxe a validação
    # junto com o resto da cascata. O par estático fica de fora (herda o
    # `user_id` do limite, que pode ser nulo); a operação do operador, não.
    # A associação chama-se `author` (a COLUNA é `user_id`).
    author factory: :user
    risk_control
    project { risk_control.project }
    company { risk_control.company }
    carrier { risk_control.carrier }
    operation_type { risk_control.risk_operation_type }
    operation_subtype { risk_control.risk_operation_type.default_subtype }
    sequence(:title) { |n| "Operação #{n}" }
    issue_date { Date.new(2026, 3, 1) }
    due_date { Date.new(2026, 6, 30) }
    operation_value { 100_000.00 }
    original_balance { 100_000.00 }
    balance { 0 }
    agreed_rate { 2.55 }

    # **S7 / B-09** — o `after_create` da operação lança o movimento
    # "Liberação do Recurso" resolvido por `integration_key`, e o tipo
    # funcional é **dado de referência**, não de fixture. Sem ele
    # `RiskMovementType.release` levanta `MissingFunctionalType` — que é
    # exatamente o portão que a S5 desenhou para o dia em que alguém
    # renomeasse o tipo pela tela. Semeando aqui, toda factory de operação
    # exercita o caminho real em vez de contorná-lo.
    before(:create) do
      unless ::RiskMovementType.exists?(integration_key: ::RiskMovementType::RELEASE_KEY)
        ::Seeds::Reference::RiskMovementTypes.call!
      end
    end

    trait :encerrada do
      is_ended { true }
    end
  end

  factory :risk_movement do
    risk_operation
    movement_type factory: :risk_movement_type
    date { Date.new(2026, 3, 1) }
    movement_value { 1_000.00 }
    balance { 0 }
  end

  factory :risk_entry do
    risk_control
    company { risk_control.company }
    project { risk_control.project }
    date { Date.new(2026, 3, 31) }
    vencidos_value { 0 }
    a_vencer_value { 0 }
    liquidacao_value { 0 }
    descontos_value { 0 }
    comissaria_vencidos_value { 0 }
    comissaria_a_vencer_value { 0 }
    fomento_vencidos_value { 0 }
    fomento_a_vencer_value { 0 }
    intercompany_vencidos_value { 0 }
    intercompany_a_vencer_value { 0 }
  end
end
