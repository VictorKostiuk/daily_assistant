FactoryBot.define do
  factory :telegram_account do
    user
    sequence(:telegram_user_id) { |n| 900_000_000 + n }
    telegram_chat_id { telegram_user_id }
    first_name { "Ada" }
  end
end
