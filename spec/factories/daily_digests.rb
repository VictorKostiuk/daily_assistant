FactoryBot.define do
  factory :daily_digest do
    user
    enabled { true }
    delivery_time { "08:00" }
    time_zone { "Europe/Rome" }
  end
end
