# frozen_string_literal: true

# S8 — as factories da unidade de **operações estruturadas e remuneração**.
#
# Três regras que valem para todas elas:
#
# 1. **`structured_operation_type` é catálogo GLOBAL** — não tem `project`. Se
#    você veio acrescentar um, leia `app/models/concerns/global_catalog.rb`: a
#    regra é o oposto da de `structured_operation`, e as duas estão certas.
# 2. **`structured_operation` deriva o `project_id` da empresa** em todo save
#    (`before_validation`). Declarar `project` na factory é decorativo: quem
#    manda é `company.project_id`. Por isso a empresa nasce **dentro** do
#    projeto pedido.
# 3. **`remuneration` é polimórfica.** O default é a classe **EST**
#    (`StructuredOperationType`); o trait `:liquidavel` troca para a **LIQ**
#    (`RiskOperationType`), e é ele que exercita o outro lado da mesma fórmula.
FactoryBot.define do
  factory :structured_operation_type do
    sequence(:title) { |n| "Tipo estruturado #{n}" }

    trait :semeado do
      is_default { true }
    end

    trait :inativo do
      is_active { false }
    end
  end

  factory :structured_operation do
    project
    company { association :company, project: project }
    carrier
    operation_type factory: :structured_operation_type
    author factory: :user
    sequence(:title) { |n| "Operação estruturada #{n}" }
    contract_number { 'CT-0001' }
    issue_date { Date.new(2026, 3, 1) }
    due_date { Date.new(2026, 6, 30) }
    operation_value { BigDecimal('200000.00') }
    original_balance { BigDecimal('50000.00') }
    agreed_rate { BigDecimal('2.55') }

    # **Q-R18 / golden E7** — encerrada CONTINUA candidata a recibo. O trait
    # existe para que o teste diga isso com todas as letras.
    # ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115 · fonte:
    # `../sfg/app/models/receipt.rb:27-35` (`available_for_receipt` filtra por
    # `receipt_id`, e NÃO por `is_ended`). Fonte, não oráculo.
    trait :encerrada do
      is_ended { true }
    end

    trait :no_variavel do
      is_on_variable { true }
    end
  end

  factory :remuneration do
    project
    operation_type factory: :structured_operation_type
    value { BigDecimal('2.55') }

    # A classe **LIQ**: a mesma remuneração, do outro lado da hierarquia. É o
    # que o contrato **C3** manda testar — os dois lados, não só o confortável.
    trait :liquidavel do
      operation_type factory: :risk_operation_type
    end
  end
end
