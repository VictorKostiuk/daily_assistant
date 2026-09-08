module Reminders
  class Create
    def self.call(user:, title:, scheduled_at:, remindable: nil, offset_minutes: nil, source: :telegram, metadata: nil)
      new(
        user: user,
        title: title,
        scheduled_at: scheduled_at,
        remindable: remindable,
        offset_minutes: offset_minutes,
        source: source,
        metadata: metadata
      ).call
    end

    def initialize(user:, title:, scheduled_at:, remindable:, offset_minutes:, source:, metadata:)
      @user = user
      @title = title
      @scheduled_at = scheduled_at
      @remindable = remindable
      @offset_minutes = offset_minutes
      @source = source
      @metadata = metadata
    end

    def call
      user.reminders.create!(
        title: title,
        scheduled_at: scheduled_at,
        remindable: remindable,
        offset_minutes: offset_minutes,
        time_zone: time_zone,
        source: source,
        metadata: SourceMetadata.dump(metadata),
        status: :pending
      )
    end

    private

    attr_reader :user, :title, :scheduled_at, :remindable, :offset_minutes, :source, :metadata

    def time_zone
      user.time_zone.presence || Time.zone.name
    end
  end
end
