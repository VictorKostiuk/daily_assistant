FactoryBot.define do
  factory :calendar_event do
    user
    provider { "google" }
    sequence(:external_event_id) { |n| "gcal_event_#{n}" }
    title { "Team meeting" }
    starts_at { 1.day.from_now.change(hour: 10, min: 0) }
    ends_at { 1.day.from_now.change(hour: 10, min: 30) }
    all_day { false }
    time_zone { "Europe/Rome" }
    status { :confirmed }
  end
end
