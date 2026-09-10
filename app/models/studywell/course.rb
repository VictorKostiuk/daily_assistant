module Studywell
  class Course < ApplicationRecord
    belongs_to :user
    has_many :obligations, dependent: :restrict_with_exception

    validates :name, presence: true
    validates :colour, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_nil: true
    validate :active_dates_ordered

    private

    def active_dates_ordered
      return if active_from.nil? || active_until.nil?
      return if active_from <= active_until

      errors.add(:active_until, "is invalid")
    end
  end
end
