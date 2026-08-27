# frozen_string_literal: true

module Api
  module Entities
    class AuthResponse < Grape::Entity
      expose :user, using: Api::Entities::User
      expose :token
      # refresh_token NÃO é exposto: vai em cookie HttpOnly (ver AuthHelpers).
      # O valor cru continua acessível ao controller por entity.object.
    end
  end
end
