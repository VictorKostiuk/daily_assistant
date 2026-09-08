FactoryBot.define do
  factory :reminder_preference do
    user
    event_reminder_mode { :ask_every_time }
    default_event_offset_minutes { 30 }
  end
end
