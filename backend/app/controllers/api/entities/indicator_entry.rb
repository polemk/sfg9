# frozen_string_literal: true

module Api
  module Entities
    # S10 / BE-326 — o lançamento mensal.
    #
    # `value` sai como **string** de propósito: é `decimal(15,2)` e passar por
    # float no JSON é o caminho para `1234.56` virar `1234.5599999999999`. O
    # front formata com `Intl` (DEC-10).
    class IndicatorEntry < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :indicator_id, documentation: { type: 'String' }
      expose :year, documentation: { type: 'Integer' }
      expose :month, documentation: { type: 'Integer', desc: '1..12. CHECK no banco.' }
      expose :value, documentation: { type: 'String', desc: 'Decimal como string. Aceita negativos.' } do |e|
        e.value&.to_s
      end
      expose :title, documentation: { type: 'String', desc: 'Foto do título do indicador no momento (T-D11).' }
      expose :value_type, documentation: { type: 'String' }
      expose :created_by, documentation: { type: 'String', desc: 'Quem lançou. Vem da SESSÃO (corrige BE-326).' }
      expose :updated_by, documentation: { type: 'String', desc: 'Quem alterou por último.' }
      expose :created_at
      expose :updated_at
    end
  end
end
