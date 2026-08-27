# frozen_string_literal: true

module Api
  module Entities
    # S3 / BE-074 — grupo de portadores.
    #
    # `carriers_count` é o `counter_cache` (OPS-058) e é **o mesmo número** que
    # decide o 422 da exclusão no servidor. No legado a contagem divergia da
    # lista e mesmo assim era ela que escondia o botão.
    class CarrierGroup < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String' }
      expose :integration_key, documentation: { type: 'String' }
      expose :carriers_count, documentation: { type: 'Integer', desc: 'Portadores no grupo (counter_cache)' }
      expose :is_active, documentation: { type: 'Boolean' }
      expose :created_at
      expose :updated_at
    end
  end
end
