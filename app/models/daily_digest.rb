class DailyDigest < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true

  scope :enabled, -> { where(enabled: true) }

  # delivery_time is a time-zone-aware :time column, so reading it outside a
  # Time.use_zone(this digest's own zone) block silently returns the wall-clock
  # hour/min in whatever zone happens to be globally active at read time.
  def local_delivery_time
    Time.use_zone(time_zone.presence || Time.zone.name) { delivery_time }
  end
end
