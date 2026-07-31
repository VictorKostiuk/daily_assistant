module Integrations
  module Google
    class CancelEvent
      DEFAULT_CALENDAR_ID = "primary".freeze

      def self.call(user:, event_id:)
        new(user: user, event_id: event_id).call
      end

      def initialize(user:, event_id:)
        @user = user
        @event_id = event_id
      end

      def call
        client.calendar.delete_event(calendar_id, event_id)
        LocalCalendarEvent.cancel(user: user, external_event_id: event_id)
      end

      private

      attr_reader :user, :event_id

      def client
        @client ||= Integrations::Google::Client.new(user.google_integration)
      end

      def calendar_id
        user.user_setting&.default_calendar_id.presence || DEFAULT_CALENDAR_ID
      end
    end
  end
end
