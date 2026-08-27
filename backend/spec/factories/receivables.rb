# frozen_string_literal: true

# S6 — as factories do bloco de recebíveis.
#
# **A regra que vale para todas: o borderô NÃO nasce calculado.** A factory
# monta as entradas digitáveis e deixa os ~33 derivados como estão. Quem calcula
# é `Receivables::CreateService` / `UpdateService`, chamando o
# `Receivables::Calculator` **uma vez** (contrato C2). Uma factory que
# preenchesse `valor_liquido` à mão criaria uma segunda fonte de verdade dentro
# da própria suíte — que é exatamente o defeito que a fatia existe para fechar.
#
# Para um borderô **com os derivados preenchidos**, use o trait `:calculado`:
# ele chama o mesmo serviço que a tela chama.
FactoryBot.define do
  factory :wallet do
    sequence(:title) { |n| "Carteira #{n}" }
  end

  factory :receivable_kind do
    sequence(:title) { |n| "Tipo de recebível #{n}" }
  end

  factory :resource_source do
    sequence(:title) { |n| "Fonte de recurso #{n}" }
  end

  factory :movement_kind do
    sequence(:title) { |n| "Tarifa #{n}" }
    kind { MovementKind::KIND_DEBIT }
    is_operation { true }

    trait :advalorem do
      title { 'AdValorem' }
      is_advalorem { true }
    end

    trait :desagio do
      title { 'Desagio' }
      is_desagio { true }
    end

    trait :iof do
      title { 'IOF' }
      is_iof { true }
    end
  end

  factory :iof_rate do
    daily_rate { BigDecimal('0.000041') }
    fixed_rate { BigDecimal('0.0038') }
    valid_from { Date.new(2016, 1, 1) }
  end

  factory :receivable_entry do
    project
    company { association :company, project: project }
    carrier
    wallet
    receivable_kind
    resource_source
    author { association :user }
    date { Date.current }
    sequence(:nro_bordero) { |n| n.to_s }

    valor_bruto { BigDecimal('100000.00') }
    vlr_bruto_recusado { 0 }
    qtd_titulos { 10 }
    qtd_recusada { 0 }
    prz_med_pond_emp { BigDecimal('30') }
    prz_med_pond_bco { BigDecimal('32') }
    float_acordado { BigDecimal('2') }
    cst_efetivo_acordado { BigDecimal('2.5') }

    # O portador precisa estar conectado ao projeto — é o mesmo critério que o
    # servidor aplica, e é o **único** critério (não invente um segundo: foi
    # ter dois que fez a tela do legado oferecer portador que o servidor
    # recusava).
    after(:build) do |entry|
      if entry.project && entry.carrier &&
         !ProjectToCarrierConnection.exists?(project_id: entry.project.id, carrier_id: entry.carrier.id)
        create(:project_to_carrier_connection, project: entry.project, carrier: entry.carrier)
      end
    end

    # Passa pelo MESMO serviço da tela. É o que garante que o registro de teste
    # e o registro de produção nasçam pelo mesmo caminho.
    trait :calculado do
      transient do
        taxas { [] }
      end

      after(:create) do |entry, evaluator|
        Receivables::UpdateService.call(
          project: entry.project, id: entry.id, actor: entry.author,
          attrs: {}, taxes: evaluator.taxas
        )
        entry.reload
      end
    end
  end

  factory :receivable_tax do
    receivable_entry
    movement_kind
    value { BigDecimal('100.00') }
  end

  factory :charge do
    project
    author { association :user }
    date { Date.current }
    state { Charge::STATE_EDITING }
  end
end
