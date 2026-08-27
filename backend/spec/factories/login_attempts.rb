FactoryBot.define do
  factory :login_attempt do
    identifier { Faker::Internet.email }
    add_attribute(:method) { 'email' }
    ip_address { Faker::Internet.ip_v4_address }
    user_agent { Faker::Internet.user_agent }
    success { false }
    error_reason { nil }
    
    trait :successful do
      success { true }
    end
  end
end
