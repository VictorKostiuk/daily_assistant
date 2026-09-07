module Integrations
  module Google
    class LocalCalendarEvent
      PROVIDER = "google".freeze

      class PersistenceError < StandardError
        attr_reader :provider_event_id

        def initialize(original, provider_event_id:)
          @provider_event_id = provider_event_id
          super(original.message)
          set_backtrace(original.backtrace) if original.backtrace
        end
      end

      def self.sync(user:, external_event_id:, external_calendar_id:, event:, time_zone:, status: :confirmed, metadata: nil)
        record = ::CalendarEvent.find_or_initialize_by(
          user: user,
          provider: PROVIDER,
          external_calendar_id: external_calendar_id,
          external_event_id: external_event_id
        )
        attributes = {
          title: event.title,
          description: event.description,
          location: event.location,
          starts_at: event.starts_at,
          ends_at: event.ends_at,
          all_day: event.all_day,
          time_zone: time_zone,
          status: status,
          user_integration: user.google_integration,
          synced_at: Time.current
        }
        attributes[:metadata] = SourceMetadata.merge(record.metadata, metadata) unless metadata.nil?
        record.assign_attributes(attributes)
        record.save!
      rescue SourceMetadata::Invalid
        raise
      rescue StandardError => error
        Rails.logger.error("[integrations] failed to sync local calendar_event: #{error.class}: #{error.message}")
        raise PersistenceError.new(error, provider_event_id: external_event_id)
      end

      def self.cancel(user:, external_event_id:, external_calendar_id:)
        ::CalendarEvent.find_by(
          user: user,
          provider: PROVIDER,
          external_calendar_id: external_calendar_id,
          external_event_id: external_event_id
        )&.update!(status: :cancelled, cancelled_at: Time.current, synced_at: Time.current)
      rescue StandardError => error
        Rails.logger.error("[integrations] failed to sync local calendar_event cancellation: #{error.class}: #{error.message}")
        raise PersistenceError.new(error, provider_event_id: external_event_id)
      end
    end
  end
end
