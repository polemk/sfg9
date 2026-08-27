# frozen_string_literal: true

FactoryBot.define do
  factory :permission_audit_log do
    association :user
    change_type { 'granted' }
  end
end
