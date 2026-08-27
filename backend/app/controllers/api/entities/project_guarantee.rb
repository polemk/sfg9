# frozen_string_literal: true

module Api
  module Entities
    # S4 / BE-118 — **garantia do projeto**.
    #
    # `value` sai como **número** (string decimal), não formatado: formatação é
    # da tela. O legado devolvia `"R$ 1.234,56"` do servidor e a tela tinha de
    # desfazer a máscara para somar.
    class ProjectGuarantee < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :project_id, documentation: { type: 'String', desc: 'Projeto dono. NUNCA aceito no corpo (C1)' }
      expose :title, documentation: { type: 'String' }
      expose :value, documentation: { type: 'String', desc: 'decimal(14,2). Número, nunca texto formatado' }
      expose :observation, documentation: { type: 'String', desc: 'TEXT — era string(255) e truncava (DB-083)' }

      expose :carrier_id
      expose :carrier_title, documentation: { type: 'String' } do |g|
        g.carrier&.title
      end
      expose :carrier_group_title, documentation: { type: 'String' } do |g|
        g.carrier&.group&.title
      end

      expose :guarantee_type_id
      expose :guarantee_type_title, documentation: { type: 'String' } do |g|
        g.guarantee_type&.title
      end
      expose :guarantee_type_is_provisional,
             documentation: { type: 'Boolean', desc: 'DEC-86 — o tipo foi semeado como suposição' } do |g|
        g.guarantee_type&.is_provisional
      end

      expose :created_at
      expose :updated_at
    end
  end
end
