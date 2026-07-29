module Integrations
  module Google
    class CreateEvent
      DEFAULT_CALENDAR_ID = "primary".freeze

      def self.call(user:, event:)
        new(user: user, event: event).call
      end

      def initialize(user:, event:)
        @user = user
        @event = event
      end

      def call
        client.calendar.insert_event(calendar_id, payload)
      end

      private

      attr_reader :user, :event

      def payload
        ::Google::Apis::CalendarV3::Event.new(
          summary: event.title,
          description: event.description,
          location: event.location,
          start: date_time_for(event.starts_at),
          end: date_time_for(event.ends_at, closing: true)
        )
      end

      def date_time_for(time, closing: false)
        return ::Google::Apis::CalendarV3::EventDateTime.new(date_time: time.iso8601, time_zone: time_zone) unless event.all_day

        date = closing ? time.to_date + 1 : time.to_date
        ::Google::Apis::CalendarV3::EventDateTime.new(date: date.iso8601)
      end

      def client
        @client ||= Integrations::Google::Client.new(user.google_integration)
      end

      def calendar_id
        user.user_setting&.default_calendar_id.presence || DEFAULT_CALENDAR_ID
      end

      def time_zone
        @time_zone ||= user.time_zone.presence || Time.zone.name
      end
    end
  end
end
