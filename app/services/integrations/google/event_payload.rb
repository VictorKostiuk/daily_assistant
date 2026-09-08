module Integrations
  module Google
    class EventPayload
      ALL_KEYS = %w[title description location starts_at ends_at all_day].freeze
      TIMING_KEYS = %w[starts_at ends_at all_day].freeze

      def self.build(event, time_zone:, only: nil)
        new(event, time_zone, only: only).build
      end

      def self.from_provider(google_event, time_zone:)
        timed_start = google_event.start&.date_time
        all_day = timed_start.nil?

        Integrations::OpenRouter::EventParsing::Event.new(
          title: google_event.summary.to_s.strip,
          description: google_event.description.presence,
          location: google_event.location.to_s.strip.presence,
          starts_at: all_day ? date_in_zone(google_event.start&.date, time_zone) : time_in_zone(timed_start, time_zone),
          ends_at: all_day ? inclusive_end_in_zone(google_event.end&.date, time_zone) : time_in_zone(google_event.end&.date_time, time_zone),
          all_day: all_day
        )
      end

      def initialize(event, time_zone, only: nil)
        @event = event
        @time_zone = time_zone
        @only = only&.map(&:to_s)
      end

      def build
        ::Google::Apis::CalendarV3::Event.new(**payload_attributes)
      end

      private

      attr_reader :event, :time_zone, :only

      def payload_attributes
        attributes = {}
        attributes[:summary] = field("title") if include_key?("title")
        attributes[:description] = field("description") if include_key?("description")
        attributes[:location] = field("location") if include_key?("location")

        if include_timing?
          attributes[:start] = date_time_for(field("starts_at"))
          attributes[:end] = date_time_for(field("ends_at"), closing: true)
        end

        attributes
      end

      def include_key?(key)
        keys.include?(key)
      end

      def include_timing?
        (keys & TIMING_KEYS).any?
      end

      def sparse?
        !only.nil?
      end

      def keys
        @keys ||= only || ALL_KEYS
      end

      def field(name)
        if event.respond_to?(:key?)
          return event[name] if event.key?(name)
          return event[name.to_sym] if event.key?(name.to_sym)

          nil
        else
          event.public_send(name)
        end
      end

      def all_day?
        value = field("all_day")
        value == true
      end

      def date_time_for(time, closing: false)
        if all_day?
          date = closing ? time.to_date + 1 : time.to_date
          args = { date: date.iso8601 }
          if sparse?
            args[:date_time] = nil
            args[:time_zone] = nil
          end
          ::Google::Apis::CalendarV3::EventDateTime.new(**args)
        else
          args = { date_time: time.iso8601, time_zone: time_zone }
          args[:date] = nil if sparse?
          ::Google::Apis::CalendarV3::EventDateTime.new(**args)
        end
      end

      def self.date_in_zone(value, time_zone)
        parsed = parse_date(value)
        parsed&.in_time_zone(time_zone)
      end

      def self.inclusive_end_in_zone(value, time_zone)
        parsed = parse_date(value)
        parsed && (parsed - 1).in_time_zone(time_zone)
      end

      def self.time_in_zone(value, time_zone)
        return if value.blank?

        coerced = value.respond_to?(:in_time_zone) ? value : Time.iso8601(value.to_s)
        coerced.in_time_zone(time_zone)
      end

      def self.parse_date(value)
        return if value.blank?
        return value if value.is_a?(Date) && !value.is_a?(DateTime)

        Date.parse(value.to_s)
      end
      private_class_method :date_in_zone, :inclusive_end_in_zone, :time_in_zone, :parse_date
    end
  end
end
