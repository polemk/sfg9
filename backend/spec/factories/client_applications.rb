# frozen_string_literal: true

FactoryBot.define do
  factory :client_application do
    sequence(:name) { |n| "Client App #{n}" }
    sequence(:token) { |n| "token_#{n}" }
    active { true }
  end
end
