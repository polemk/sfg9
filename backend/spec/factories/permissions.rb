FactoryBot.define do
  factory :permission do
    key { "permission_#{SecureRandom.hex(4)}" }
    title { 'Test Permission' }
    is_active { true }

    trait :download_basic do
      key { 'download_basic' }
      title { 'Download Basic' }
    end

    trait :download_full do
      key { 'download_full' }
      title { 'Download Full' }
    end

    trait :discord_access do
      key { 'discord_access' }
      title { 'Discord Access' }
    end
  end
end
