# frozen_string_literal: true

module Api
  module Entities
    # S12 / DB-367 — grupo da ajuda, com a ordem **persistida**.
    class HelpGroup < Grape::Entity
      expose :id
      expose :title
      expose :position
      expose :categories, using: Api::Entities::HelpCategory, if: ->(_g, opts) { opts[:with_categories] } do |g|
        g.categories.sort_by { |c| [c.position, c.title.to_s] }
      end
    end
  end
end
