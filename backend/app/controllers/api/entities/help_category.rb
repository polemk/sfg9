# frozen_string_literal: true

module Api
  module Entities
    # S12 / DB-368 — categoria da ajuda. O `slug` é **coluna**, não cálculo.
    class HelpCategory < Grape::Entity
      expose :id
      expose :title
      expose :slug
      expose :help_group_id
      expose :position
      expose :items_count do |c, opts|
        opts[:items_count] || c.items.size
      end
    end
  end
end
