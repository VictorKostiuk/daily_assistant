class UserIntegration < ApplicationRecord
  enum :status, {
  pending: 0,
  connected: 1,
  expired: 2,
  revoked: 3,
  error: 4
}
end
