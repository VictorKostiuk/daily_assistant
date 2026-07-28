class NotificationDelivery < ApplicationRecord
  enum :channel, {
    telegram: 0,
    web: 1,
    email: 2,
    push: 3
  }

  enum :status, {
    pending: 0,
    processing: 1,
    delivered: 2,
    failed: 3,
    cancelled: 4
  }
end
