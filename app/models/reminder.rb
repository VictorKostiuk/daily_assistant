class Reminder < ApplicationRecord
  belongs_to :user
  belongs_to :remindable, polymorphic: true, optional: true
  belongs_to :user_integration, optional: true
  belongs_to :action_execution, optional: true

  has_many :notification_deliveries,
           as: :deliverable,
           dependent: :destroy

  enum :status, {
    pending: 0,
    processing: 1,
    delivered: 2,
    cancelled: 3,
    failed: 4
  }

  enum :source, {
    web: 0,
    telegram: 1,
    calendar_sync: 2,
    system: 3
  }
end
