FactoryBot.define do
  factory :action_execution do
    user
    action_type { "setup_event" }
    source { :telegram }
    status { :succeeded }
  end
end
