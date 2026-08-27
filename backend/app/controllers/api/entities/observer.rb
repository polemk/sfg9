# frozen_string_literal: true

module Api
  module Entities
    # S2 / BE-426 — observador e os contextos que ele acompanha.
    class Observer < Grape::Entity
      expose :id
      expose :name
      expose :email
      expose :is_internal
      expose :contexts do |o|
        o.observer_contexts.map(&:context)
      end
      expose :created_at
      expose :updated_at
    end
  end
end
