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
        created = client.calendar.insert_event(calendar_id, payload)

        LocalCalendarEvent.sync(
          user: user,
          external_event_id: created.id,
          external_calendar_id: calendar_id,
          event: event,
          time_zone: time_zone
        )

        created
      end

      private

      attr_reader :user, :event

      def payload
        EventPayload.build(event, time_zone: time_zone)
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
