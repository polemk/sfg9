module Api
  module Entities
    class Credential < Grape::Entity
      expose :id
      expose :name
      expose :provider
      expose :masked_api_key, as: :api_key_masked
      expose :created_at
      expose :updated_at

      # IMPORTANT: Never expose :api_key directly!
    end
  end
end
