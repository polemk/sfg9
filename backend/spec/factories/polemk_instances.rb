# frozen_string_literal: true

FactoryBot.define do
  factory :polemk_instance do
    sequence(:display_name) { |n| "Instance #{n}" }
    sequence(:instance_name) { |n| "INSTANCE_#{n}" }
    sequence(:instance_id) { |n| "id_#{n}" }
    api_key { 'secret_key' }
    connection_status { 'disconnected' }
  end
end
