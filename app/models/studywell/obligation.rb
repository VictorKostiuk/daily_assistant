module Studywell
  class Obligation < ApplicationRecord
    belongs_to :user
    belongs_to :course

    enum :kind, {
      assignment: 0,
      exam: 1,
      study_task: 2
    }

    enum :status, {
      open: 0,
      done: 1
    }

    enum :importance, {
      low: 0,
      normal: 1,
      high: 2
    }

    validates :title, presence: true
    validates :estimated_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :progress_percent,
              numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
              allow_nil: true
    validate :course_owner_matches
    validate :timing_matches_kind

    def remaining_minutes
      return if estimated_minutes.nil? || progress_percent.nil?

      ((estimated_minutes * (100 - progress_percent)) / 100.0).ceil
    end

    private

    def course_owner_matches
      return if user_id.nil? || course.nil?
      return if course.user_id == user_id

      errors.add(:course, "is invalid")
    end

    def timing_matches_kind
      case kind
      when "assignment"
        errors.add(:starts_at, "is invalid") if starts_at
        errors.add(:ends_at, "is invalid") if ends_at
      when "exam"
        errors.add(:due_at, "is invalid") if due_at
        validate_interval_pair
      when "study_task"
        validate_interval_pair
        errors.add(:ends_at, "is invalid") if due_at && ends_at && ends_at > due_at
      end
    end

    def validate_interval_pair
      if starts_at.nil? ^ ends_at.nil?
        errors.add(:ends_at, "is invalid")
      elsif starts_at && ends_at && ends_at <= starts_at
        errors.add(:ends_at, "is invalid")
      end
    end
  end
end
