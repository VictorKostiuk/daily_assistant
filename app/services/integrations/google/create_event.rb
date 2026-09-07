module Integrations
  module Google
    class CreateEvent
      DEFAULT_CALENDAR_ID = "primary".freeze

      # The provider event, plus the calendar this operation actually selected.
      # A caller that needs the local row must look it up with this calendar id:
      # the provider event id alone does not identify a row, because the unique
      # index is (user, provider, external_calendar_id, external_event_id).
      Result = Struct.new(:provider_event, :calendar_id, keyword_init: true)

      def self.call(user:, event:, metadata: nil)
        new(user: user, event: event, metadata: metadata).call
      end

      def initialize(user:, event:, metadata:)
        @user = user
        @event = event
        @metadata = metadata
      end

      def call
        SourceMetadata.dump(metadata)
        created = client.calendar.insert_event(calendar_id, payload)

        LocalCalendarEvent.sync(
          user: user,
          external_event_id: created.id,
          external_calendar_id: calendar_id,
          event: EventPayload.from_provider(created, time_zone: time_zone),
          time_zone: time_zone,
          metadata: metadata
        )

        Result.new(provider_event: created, calendar_id: calendar_id)
      end

      private

      attr_reader :user, :event, :metadata

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
