class ApiToken < ApplicationRecord
  TTL = 30.days

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def self.issue!(user:)
    token = SecureRandom.urlsafe_base64(32)
    record = create!(user: user, token_digest: digest(token), expires_at: TTL.from_now)
    [ token, record ]
  end

  def self.find_usable(token)
    return if token.blank?

    record = find_by(token_digest: digest(token))
    return if record.nil? || record.revoked_at.present? || record.expires_at <= Time.current

    record
  end

  def self.digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end
end
