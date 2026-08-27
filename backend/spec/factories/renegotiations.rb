# frozen_string_literal: true

# S9 — fábricas das renegociações.
#
# **`operation_interest_rate` nasce ZERO de propósito.** Com taxa > 0 o VP
# sobrescreve `current_installment_value` (D-46) em toda renegociação criada, e
# metade dos exemplos passaria a medir o VP sem querer. Quem testa o VP declara a
# taxa; quem não testa fica com a aritmética simples.
FactoryBot.define do
  factory :renegotiation do
    project
    provider { association :provider, project: project }
    company { association :company, project: project }
    sequence(:title) { |n| "Renegociação #{n}" }
    kind { ::Renegotiation::KIND_FINANCEIRO }
    renegotiation_date { Date.new(2025, 1, 10) }
    original_value { 100_000.00 }
    total_debt { 120_000.00 }
    operation_interest_rate { 0.0 }
    sequence(:integration_key) { |n| "reneg_#{n}" }

    trait :com_juros do
      operation_interest_rate { 1.5 }
    end
  end

  factory :renegotiation_installment do
    renegotiation
    project { renegotiation.project }
    due_date { Date.new(2025, 2, 10) }
    main_value { 1_000.00 }
    interest_value { 0.0 }
    monetary_correction_value { 0.0 }
    batch_token { SecureRandom.uuid }
    color { '#4d1717' }

    # Os derivados saem das MESMAS fórmulas que a gravação usa. Escrevê-los à mão
    # na fábrica seria criar uma terceira definição da conta — e ela ficaria
    # certa até a primeira mudança.
    after(:build) do |parcela|
      Renegotiations::Formulas.installment(
        main_value: parcela.main_value,
        interest_value: parcela.interest_value,
        monetary_correction_value: parcela.monetary_correction_value
      ).each { |campo, valor| parcela.public_send(:"#{campo}=", valor) }
    end
  end

  factory :renegotiation_payment do
    renegotiation_installment
    renegotiation { renegotiation_installment.renegotiation }
    project { renegotiation_installment.project }
    date { Date.new(2025, 2, 10) }
    installment_paid_value_with_interest_cm { 1_000.00 }
    late_payment_value { 0.0 }
    payment_number { 1 }
  end

  factory :renegotiation_attachment do
    renegotiation
    project { renegotiation.project }
    author factory: :user
    title { 'Contrato assinado' }

    after(:build) do |anexo|
      unless anexo.file.attached?
        anexo.file.attach(
          io: File.open(Rails.root.join('spec/fixtures/files/sample.pdf')),
          filename: 'contrato.pdf', content_type: 'application/pdf'
        )
      end
    end
  end
end
