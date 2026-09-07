FactoryBot.define do
  factory :user_integration do
    user
    association :integration_provider, factory: :google_integration_provider
    status { :connected }
    scopes { [ "https://www.googleapis.com/auth/calendar" ] }
    access_token { "test-access-token" }
    refresh_token { "test-refresh-token" }
    connected_at { Time.current }
  end
end
