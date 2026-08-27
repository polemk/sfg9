FactoryBot.define do
  factory :user_permission do
    association :user
    association :permission
    source { 'manual' }
    granted_at { Time.current }
  end
end
