module Integrations
  module Google
    class LocalCalendarEvent
      PROVIDER = "google".freeze

      def self.sync(user:, external_event_id:, external_calendar_id:, event:, time_zone:, status: :confirmed)
        record = ::CalendarEvent.find_or_initialize_by(user: user, provider: PROVIDER, external_event_id: external_event_id)
        record.assign_attributes(
          external_calendar_id: external_calendar_id,
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
        )
        record.save!
      rescue StandardError => error
        Rails.logger.error("[integrations] failed to sync local calendar_event: #{error.class}: #{error.message}")
      end

      def self.cancel(user:, external_event_id:)
        ::CalendarEvent.find_by(user: user, provider: PROVIDER, external_event_id: external_event_id)
          &.update!(status: :cancelled, cancelled_at: Time.current, synced_at: Time.current)
      rescue StandardError => error
        Rails.logger.error("[integrations] failed to sync local calendar_event cancellation: #{error.class}: #{error.message}")
      end
    end
  end
end
