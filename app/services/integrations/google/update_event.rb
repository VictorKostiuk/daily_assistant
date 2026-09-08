module Integrations
  module Google
    class UpdateEvent
      DEFAULT_CALENDAR_ID = "primary".freeze

      def self.call(user:, event_id:, event: nil, metadata: nil, sparse_attrs: nil)
        new(user: user, event_id: event_id, event: event, metadata: metadata, sparse_attrs: sparse_attrs).call
      end

      def initialize(user:, event_id:, event:, metadata:, sparse_attrs:)
        @user = user
        @event_id = event_id
        @event = event
        @metadata = metadata
        @sparse_attrs = sparse_attrs
      end

      def call
        SourceMetadata.dump(metadata)
        updated = if sparse?
          client.calendar.patch_event(calendar_id, event_id, sparse_payload)
        else
          client.calendar.update_event(calendar_id, event_id, payload)
        end

        LocalCalendarEvent.sync(
          user: user,
          external_event_id: updated.id,
          external_calendar_id: calendar_id,
          event: EventPayload.from_provider(updated, time_zone: time_zone),
          time_zone: time_zone,
          metadata: metadata
        )

        updated
      end

      private

      attr_reader :user, :event_id, :event, :metadata, :sparse_attrs

      def sparse?
        !sparse_attrs.nil?
      end

      def payload
        EventPayload.build(event, time_zone: time_zone)
      end

      def sparse_payload
        keys = sparse_attrs.keys.map(&:to_s) & EventPayload::ALL_KEYS
        EventPayload.build(sparse_attrs, time_zone: time_zone, only: keys)
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
