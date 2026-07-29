class UserIntegration < ApplicationRecord
  belongs_to :user
  belongs_to :integration_provider

  encrypts :access_token
  encrypts :refresh_token

  enum :status, {
    pending: 0,
    connected: 1,
    expired: 2,
    revoked: 3,
    error: 4
  }

  scope :for_provider, ->(key) { joins(:integration_provider).where(integration_providers: { key: key }) }

  def token_expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end

  def reconnect_required?
    expired? || revoked? || error?
  end
end
