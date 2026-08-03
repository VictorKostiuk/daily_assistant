module Reminders
  class Create
    def self.call(user:, title:, scheduled_at:, remindable: nil, offset_minutes: nil, source: :telegram)
      new(
        user: user,
        title: title,
        scheduled_at: scheduled_at,
        remindable: remindable,
        offset_minutes: offset_minutes,
        source: source
      ).call
    end

    def initialize(user:, title:, scheduled_at:, remindable:, offset_minutes:, source:)
      @user = user
      @title = title
      @scheduled_at = scheduled_at
      @remindable = remindable
      @offset_minutes = offset_minutes
      @source = source
    end

    def call
      user.reminders.create!(
        title: title,
        scheduled_at: scheduled_at,
        remindable: remindable,
        offset_minutes: offset_minutes,
        time_zone: time_zone,
        source: source,
        status: :pending
      )
    end

    private

    attr_reader :user, :title, :scheduled_at, :remindable, :offset_minutes, :source

    def time_zone
      user.time_zone.presence || Time.zone.name
    end
  end
end
