module Api
  module V1
    class InputValidator
      class Error < StandardError
        attr_reader :details

        def initialize(details)
          @details = details.transform_keys(&:to_s)
          super("Request is invalid")
        end
      end

      DATE = /\A\d{4}-\d{2}-\d{2}\z/
      OFFSET_TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/
      NAIVE_TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?\z/

      SOURCE_FIELDS = SourceMetadata::FIELDS
      REMINDER_FIELDS = (%w[title scheduled_at offset_minutes] + SOURCE_FIELDS).freeze
      CALENDAR_FIELDS = (%w[title description location starts_at ends_at all_day] + SOURCE_FIELDS).freeze
      TIMING_FIELDS = %w[starts_at ends_at all_day].freeze

      def self.reminder_create(raw, time_zone:)
        raw = stringify(raw)
        reject_unknown!(raw, REMINDER_FIELDS)
        {
          "title" => require_title!(raw),
          "scheduled_at" => require_timestamp!(raw, "scheduled_at", time_zone: time_zone),
          "offset_minutes" => optional_offset!(raw),
          "metadata" => source_attrs!(raw)
        }
      end

      def self.reminder_patch(raw, time_zone:)
        raw = stringify(raw)
        reject_empty!(raw)
        reject_unknown!(raw, REMINDER_FIELDS)

        attrs = {}
        attrs["title"] = require_title!(raw) if raw.key?("title")
        attrs["scheduled_at"] = require_timestamp!(raw, "scheduled_at", time_zone: time_zone) if raw.key?("scheduled_at")
        attrs["offset_minutes"] = optional_offset!(raw) if raw.key?("offset_minutes")
        attrs["metadata"] = source_attrs!(raw) if source_present?(raw)
        attrs
      end

      def self.calendar_create(raw, time_zone:)
        raw = stringify(raw)
        reject_unknown!(raw, CALENDAR_FIELDS)
        all_day = optional_boolean!(raw, "all_day", default: false)
        starts_at, ends_at = require_timing!(raw, all_day: all_day, time_zone: time_zone, required: true)

        {
          "title" => require_title!(raw),
          "description" => optional_text!(raw, "description"),
          "location" => optional_text!(raw, "location"),
          "starts_at" => starts_at,
          "ends_at" => ends_at,
          "all_day" => all_day,
          "metadata" => source_attrs!(raw)
        }
      end

      def self.calendar_patch(raw, time_zone:)
        raw = stringify(raw)
        reject_empty!(raw)
        reject_unknown!(raw, CALENDAR_FIELDS)

        timing_keys = TIMING_FIELDS.select { |key| raw.key?(key) }
        if timing_keys.any? && timing_keys.size != TIMING_FIELDS.size
          missing = TIMING_FIELDS - timing_keys
          raise Error.new(missing.index_with { [ "can't be blank" ] })
        end

        attrs = {}
        attrs["title"] = require_title!(raw) if raw.key?("title")
        attrs["description"] = optional_text!(raw, "description") if raw.key?("description")
        attrs["location"] = optional_text!(raw, "location") if raw.key?("location")

        if timing_keys.size == TIMING_FIELDS.size
          all_day = optional_boolean!(raw, "all_day")
          starts_at, ends_at = require_timing!(raw, all_day: all_day, time_zone: time_zone, required: true)
          attrs["all_day"] = all_day
          attrs["starts_at"] = starts_at
          attrs["ends_at"] = ends_at
        end

        attrs["metadata"] = source_attrs!(raw) if source_present?(raw)
        attrs
      end

      def self.page(raw)
        raw = stringify(raw)
        value = raw["page"]
        return 1 if value.nil?

        unless positive_integer?(value)
          raise Error.new("page" => [ "is invalid" ])
        end

        value.to_i
      end

      def self.time_range(raw)
        raw = stringify(raw)
        details = {}
        %w[from to].each do |key|
          if raw[key].blank?
            details[key] = [ "can't be blank" ]
          elsif !raw[key].is_a?(String) || !raw[key].match?(OFFSET_TIME)
            details[key] = [ "is invalid" ]
          end
        end
        raise Error.new(details) if details.any?

        from = Time.iso8601(raw["from"])
        to = Time.iso8601(raw["to"])
        raise Error.new("from" => [ "is invalid" ]) unless from < to

        [ from, to ]
      end

      def self.stringify(raw)
        raise Error.new("base" => [ "is invalid" ]) unless raw.is_a?(Hash)

        raw.stringify_keys
      end
      private_class_method :stringify

      def self.reject_unknown!(raw, allowed)
        unknown = raw.keys - allowed
        raise Error.new(unknown.index_with { [ "is unknown" ] }) if unknown.any?
      end
      private_class_method :reject_unknown!

      def self.reject_empty!(raw)
        raise Error.new("base" => [ "can't be blank" ]) if raw.blank?
      end
      private_class_method :reject_empty!

      def self.require_title!(raw)
        value = raw["title"]
        if !value.is_a?(String) || value.strip.empty?
          raise Error.new("title" => [ "can't be blank" ])
        end

        value
      end
      private_class_method :require_title!

      def self.require_timestamp!(raw, key, time_zone:)
        value = raw[key]
        parsed = parse_timestamp(value, time_zone: time_zone)
        raise Error.new(key => [ "is invalid" ]) if parsed.nil?

        parsed
      end
      private_class_method :require_timestamp!

      def self.parse_timestamp(value, time_zone:)
        return unless value.is_a?(String)

        if value.match?(OFFSET_TIME)
          Time.iso8601(value)
        elsif value.match?(NAIVE_TIME)
          Time.find_zone!(time_zone).parse(value)
        end
      rescue ArgumentError
        nil
      end
      private_class_method :parse_timestamp

      def self.parse_date(value, time_zone:)
        return unless value.is_a?(String) && value.match?(DATE)

        Date.parse(value).in_time_zone(time_zone)
      rescue ArgumentError
        nil
      end
      private_class_method :parse_date

      def self.optional_offset!(raw)
        return nil unless raw.key?("offset_minutes")

        value = raw["offset_minutes"]
        return if value.nil?
        unless value.is_a?(Integer) && value.between?(0, Reminder::MAX_OFFSET_MINUTES)
          raise Error.new("offset_minutes" => [ "is invalid" ])
        end

        value
      end
      private_class_method :optional_offset!

      def self.optional_text!(raw, key)
        return nil unless raw.key?(key)

        value = raw[key]
        return if value.nil?
        raise Error.new(key => [ "is invalid" ]) unless value.is_a?(String)

        value
      end
      private_class_method :optional_text!

      def self.optional_boolean!(raw, key, default: nil)
        return default unless raw.key?(key)

        value = raw[key]
        return value if value == true || value == false

        raise Error.new(key => [ "is invalid" ])
      end
      private_class_method :optional_boolean!

      def self.require_timing!(raw, all_day:, time_zone:, required:)
        starts_at = parse_event_time(raw["starts_at"], all_day: all_day, time_zone: time_zone)
        ends_at = parse_event_time(raw["ends_at"], all_day: all_day, time_zone: time_zone)
        details = {}
        details["starts_at"] = [ required && !raw.key?("starts_at") ? "can't be blank" : "is invalid" ] if starts_at.nil?
        details["ends_at"] = [ required && !raw.key?("ends_at") ? "can't be blank" : "is invalid" ] if ends_at.nil?
        raise Error.new(details) if details.any?

        if all_day
          raise Error.new("ends_at" => [ "is invalid" ]) unless ends_at.to_date >= starts_at.to_date
        else
          raise Error.new("ends_at" => [ "is invalid" ]) unless ends_at > starts_at
        end

        [ starts_at, ends_at ]
      end
      private_class_method :require_timing!

      def self.parse_event_time(value, all_day:, time_zone:)
        if all_day
          parse_date(value, time_zone: time_zone)
        else
          parse_timestamp(value, time_zone: time_zone)
        end
      end
      private_class_method :parse_event_time

      def self.source_present?(raw)
        SOURCE_FIELDS.any? { |field| raw.key?(field) }
      end
      private_class_method :source_present?

      def self.source_attrs!(raw)
        present = SOURCE_FIELDS.select { |field| raw.key?(field) }
        return {} if present.empty?

        attrs = raw.slice(*present)
        SourceMetadata.dump(attrs)
        attrs
      end
      private_class_method :source_attrs!

      def self.positive_integer?(value)
        case value
        when Integer
          value.positive?
        when String
          value.match?(/\A[1-9]\d*\z/)
        else
          false
        end
      end
      private_class_method :positive_integer?
    end
  end
end
