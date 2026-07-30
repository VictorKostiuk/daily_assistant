class ActionExecution < ApplicationRecord
  belongs_to :user
  belongs_to :shortcut, optional: true
  belongs_to :user_integration, optional: true

  enum :source, {
    web: 0,
    telegram: 1,
    api: 2,
    system: 3,
    admin: 4
  }

  enum :status, {
    pending: 0,
    processing: 1,
    succeeded: 2,
    failed: 3,
    cancelled: 4
  }
end
