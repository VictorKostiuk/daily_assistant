FactoryBot.define do
  factory :integration_provider do
    sequence(:key) { |n| "provider_#{n}" }
    name { "Provider" }
  end

  factory :google_integration_provider, class: "IntegrationProvider" do
    initialize_with { IntegrationProvider.google }
  end
end
