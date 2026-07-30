module Integrations
  module Google
    class EventPayload
      def self.build(event, time_zone:)
        new(event, time_zone).build
      end

      def initialize(event, time_zone)
        @event = event
        @time_zone = time_zone
      end

      def build
        ::Google::Apis::CalendarV3::Event.new(
          summary: event.title,
          description: event.description,
          location: event.location,
          start: date_time_for(event.starts_at),
          end: date_time_for(event.ends_at, closing: true)
        )
      end

      private

      attr_reader :event, :time_zone

      def date_time_for(time, closing: false)
        return ::Google::Apis::CalendarV3::EventDateTime.new(date_time: time.iso8601, time_zone: time_zone) unless event.all_day

        date = closing ? time.to_date + 1 : time.to_date
        ::Google::Apis::CalendarV3::EventDateTime.new(date: date.iso8601)
      end
    end
  end
end
