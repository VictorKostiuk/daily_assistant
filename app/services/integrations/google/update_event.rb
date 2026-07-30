module Integrations
  module Google
    class UpdateEvent
      DEFAULT_CALENDAR_ID = "primary".freeze

      def self.call(user:, event_id:, event:)
        new(user: user, event_id: event_id, event: event).call
      end

      def initialize(user:, event_id:, event:)
        @user = user
        @event_id = event_id
        @event = event
      end

      def call
        client.calendar.update_event(calendar_id, event_id, payload)
      end

      private

      attr_reader :user, :event_id, :event

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
