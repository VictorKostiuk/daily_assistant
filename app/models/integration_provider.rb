class IntegrationProvider < ApplicationRecord
  GOOGLE = "google".freeze

  GOOGLE_DEFAULTS = {
    name: "Google",
    description: "Google account access for calendar and other connected Google services."
  }.freeze

  has_many :user_integrations, dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }

  def self.google
    find_or_create_by!(key: GOOGLE) { |provider| provider.assign_attributes(GOOGLE_DEFAULTS) }
  end
end
