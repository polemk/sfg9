# frozen_string_literal: true

FactoryBot.define do
  factory :contract do
    kind { Contract::KIND_TERMS_OF_USE }
    title { 'Termos de Uso' }
    # `version` NÃO é declarada de propósito: quem a atribui é o
    # `before_validation on: :create` do model (BE-336). Uma factory que a
    # fixasse esconderia exatamente o comportamento que a fatia existe para
    # provar.
    description { '<p>Texto do contrato.</p>' }

    trait :privacy do
      kind { Contract::KIND_PRIVACY_POLICY }
      title { 'Politicas de Privacidade' }
    end
  end

  factory :contract_deal do
    user
    contract
    accepted_at { Time.current }
    source { ContractDeal::SOURCE_EXPLICIT }
    contract_kind { contract.kind }
    contract_version { contract.version }
    content_hash { contract.content_hash }
    accepted_body { contract.description_html }

    # DEC-66 — o aceite carimbado pela base antiga. Sem IP, sem user-agent e
    # sem hash: não houve requisição, e inventar prova é o que a decisão proíbe.
    trait :implicit_legacy do
      source { ContractDeal::SOURCE_IMPLICIT_LEGACY }
      content_hash { nil }
      accepted_body { nil }
      ip_address { nil }
      user_agent { nil }
      legacy_accepted_at { 3.years.ago }
      accepted_at { 3.years.ago }
    end
  end
end
