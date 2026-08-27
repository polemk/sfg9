# frozen_string_literal: true

module Api
  module Entities
    # S10 / BE-324, FE-326 — **uma linha da grade mensal**.
    #
    # A célula sem lançamento vem com `entry: null`; a lançada com zero vem com
    # `value: "0.0"`. **É aqui que "não lançado" deixa de ser indistinguível de
    # "zero"** (DEC-70) — e a distinção nasce no serviço, não numa heurística do
    # componente. No legado a view instanciava um `IndicatorEntry.new` para o mês
    # vazio e renderizava `entry.value.blank? ? 0 : entry.value`; como a coluna
    # tem default `0.0`, ausência e zero saíam idênticos.
    class IndicatorGridRow < Grape::Entity
      expose :indicator, using: Api::Entities::Indicator,
                         documentation: { type: 'Object', desc: 'O indicador da linha.' } do |row|
        row[:indicator]
      end
      expose :cells, documentation: { type: 'Array', desc: 'Uma célula por mês do período pedido.' } do |row|
        row[:cells].map do |cell|
          {
            month: cell[:month],
            # `null` = NÃO LANÇADO. Não troque por `{}` nem por `value: 0`.
            entry: cell[:entry] && Api::Entities::IndicatorEntry.represent(cell[:entry]).as_json
          }
        end
      end
    end
  end
end
