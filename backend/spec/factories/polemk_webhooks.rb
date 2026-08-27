# frozen_string_literal: true

FactoryBot.define do
  factory :polemk_webhook do
    association :polemk_instance
    url { 'http://example.com' }
    enabled { true }
    webhook_by_events { true }
    webhook_base_64 { true }
    event { 'SEND_MESSAGE' }
    raw_response { '{}' }
  end
end
