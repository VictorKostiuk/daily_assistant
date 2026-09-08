FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    first_name { "Ada" }
    last_name { "Lovelace" }
    time_zone { "Europe/Rome" }

    trait :admin do
      role { :admin }
    end

    trait :moderator do
      role { :moderator }
    end
  end
end
