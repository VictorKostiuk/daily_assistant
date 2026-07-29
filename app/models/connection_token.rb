class ConnectionToken < ApplicationRecord
  TELEGRAM = "telegram".freeze
  TTL = 15.minutes

  belongs_to :user

  validates :purpose, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :usable, -> { where(used_at: nil).where(expires_at: Time.current..) }

  def self.issue!(user:, purpose:)
    token = SecureRandom.urlsafe_base64(32)

    transaction do
      where(user: user, purpose: purpose, used_at: nil).delete_all
      create!(user: user, purpose: purpose, token_digest: digest(token), expires_at: TTL.from_now)
    end

    token
  end

  def self.claim(token, purpose:)
    record = find_by(token_digest: digest(token), purpose: purpose) if token.present?
    return if record.blank?

    claimed = usable.where(id: record.id).update_all(used_at: Time.current, updated_at: Time.current)

    record.user if claimed == 1
  end

  def self.digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end
end
