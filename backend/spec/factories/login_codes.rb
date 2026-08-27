FactoryBot.define do
  factory :login_code do
    destination { Faker::Internet.email }
    add_attribute(:method) { 'email' }
    code { '123456' }
    expires_at { 1.hour.from_now }
    
    trait :expired do
      expires_at { 1.hour.ago }
    end
  end
end
