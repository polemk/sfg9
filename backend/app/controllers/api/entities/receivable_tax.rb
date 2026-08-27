# frozen_string_literal: true

module Api
  module Entities
    # S6 / BE-184 — tarifa de um borderô.
    #
    # Título e classificadores vêm DENORMALIZADOS do registro, não do
    # `MovementKind` atual (D-B13): é a classificação usada no dia do
    # lançamento, e é ela que entrou na base do IOF.
    class ReceivableTax < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :movement_kind_id, documentation: { type: 'String', desc: 'UUID do tipo de movimentação' }
      expose :title, documentation: { type: 'String', desc: 'Título do tipo NO DIA do lançamento (D-B13)' }
      expose :value, documentation: { type: 'BigDecimal', desc: 'Valor da tarifa em R$' }
      expose :is_advalorem, documentation: { type: 'Boolean', desc: 'Classificação NO DIA do lançamento' }
      expose :is_desagio, documentation: { type: 'Boolean' }
      expose :is_iof, documentation: { type: 'Boolean' }
    end
  end
end
