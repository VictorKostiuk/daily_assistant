FactoryBot.define do
  factory :reminder do
    user
    title { "Submit the report" }
    scheduled_at { 1.hour.from_now }
    time_zone { "Europe/Rome" }
    source { :telegram }
    status { :pending }
  end
end
