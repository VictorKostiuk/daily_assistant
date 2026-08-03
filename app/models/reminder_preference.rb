class ReminderPreference < ApplicationRecord
  belongs_to :user

  enum :event_reminder_mode, {
    ask_every_time: 0,
    always_apply_default: 1,
    disabled_by_default: 2
  }
end
