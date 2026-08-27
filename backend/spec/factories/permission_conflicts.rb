# frozen_string_literal: true

FactoryBot.define do
  factory :permission_conflict do
    association :permission
    association :conflicts_with, factory: :permission
  end
end
