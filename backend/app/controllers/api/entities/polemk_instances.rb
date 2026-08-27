# frozen_string_literal: true

module Api
  module Entities
    class PolemkInstances < Grape::Entity
      expose :id
      expose :display_name
      expose :instance_id
      expose :instance_name
      expose :api_key
      expose :integration
      expose :is_qrcode
      expose :number
      expose :raw_response
      expose :connection_status
      expose :last_connection_at
      expose :last_logout_at
      expose :logout_reason
      expose :logout_initiator
      expose :qr_code
      expose :qr_expires_at
      expose :qr_session
      expose :last_qr_generated_at
      expose :created_at
      expose :updated_at
      expose :polemk_webhooks, using: Api::Entities::PolemkWebhook
    end
  end
end
