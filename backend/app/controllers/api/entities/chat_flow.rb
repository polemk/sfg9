
module Api
  module Entities
    class ChatFlow < Grape::Entity
      expose :id
      expose :name
      expose :kind
      expose :definition
      expose :agent_config
      expose :trigger_keyword

      expose :published
      expose :is_default
      expose :keywords
      expose :persona_name
      expose :persona_description
      expose :persona_avatar
      expose :credential_id
      expose :mapped_routes
      expose :override_active_chat
      expose :created_at
      expose :updated_at
    end
  end
end

