class CalendarEvent < ApplicationRecord
  belongs_to :user
  belongs_to :user_integration, optional: true
  belongs_to :action_execution, optional: true

  has_many :reminders,
           as: :remindable,
           dependent: :destroy

  enum :status, {
    confirmed: 0,
    tentative: 1,
    cancelled: 2
  }
end
