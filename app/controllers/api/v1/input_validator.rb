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
      SETTINGS_FIELDS = %w[time_zone].freeze
      COURSE_CREATE_FIELDS = %w[name code term_label colour active_from active_until].freeze
      COURSE_PATCH_FIELDS = (%w[name code term_label colour active_from active_until archived lock_version]).freeze
      LOCK_VERSION_FIELDS = %w[lock_version].freeze
      OBLIGATION_CREATE_FIELDS = %w[kind title due_at starts_at ends_at importance estimated_minutes progress_percent notes].freeze
      OBLIGATION_PATCH_FIELDS = %w[title due_at starts_at ends_at importance estimated_minutes progress_percent notes status lock_version].freeze
      COLOUR = /\A#[0-9A-Fa-f]{6}\z/
      KINDS = %w[assignment exam study_task].freeze
      IMPORTANCES = %w[low normal high].freeze
      OBLIGATION_STATUSES = %w[open done].freeze
      LIST_STATUSES = %w[open done all].freeze

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
        bounds = {}
        %w[from to].each do |key|
          value = raw[key]
          if value.blank?
            details[key] = [ "can't be blank" ]
          elsif !value.is_a?(String) || !value.match?(OFFSET_TIME)
            details[key] = [ "is invalid" ]
          else
            # OFFSET_TIME accepts shapes Time.iso8601 still rejects — month 99,
            # hour 25, offset +99:00. Without this rescue they reach the
            # controller as a bare ArgumentError, which BaseController does not
            # handle, so the caller gets a 500 instead of the promised 422.
            begin
              bounds[key] = Time.iso8601(value)
            rescue ArgumentError
              details[key] = [ "is invalid" ]
            end
          end
        end
        raise Error.new(details) if details.any?

        from = bounds["from"]
        to = bounds["to"]
        raise Error.new("from" => [ "is invalid" ]) unless from < to

        [ from, to ]
      end

      def self.time_zone_needs_setup?(value)
        return true if value.blank?
        return true unless value.is_a?(String)

        ActiveSupport::TimeZone[value].nil?
      end

      def self.signup_time_zone!(raw)
        raw = stringify(raw)
        return unless raw.key?("time_zone")

        value = raw["time_zone"]
        return if value.nil? || (value.is_a?(String) && value.blank?)
        unless value.is_a?(String)
          raise Error.new("time_zone" => [ "is invalid" ])
        end
        raise Error.new("time_zone" => [ "is invalid" ]) if ActiveSupport::TimeZone[value].nil?
      end

      def self.settings_patch(raw)
        raw = stringify(raw)
        reject_empty!(raw)
        reject_unknown!(raw, SETTINGS_FIELDS)
        { "time_zone" => require_named_time_zone!(raw["time_zone"]) }
      end

      def self.include_archived(raw)
        raw = stringify(raw)
        return false unless raw.key?("include_archived")

        value = raw["include_archived"]
        return true if value == "true"
        return false if value == "false"

        raise Error.new("include_archived" => [ "is invalid" ])
      end

      def self.obligation_list_status(raw)
        raw = stringify(raw)
        return "all" unless raw.key?("status")

        value = raw["status"]
        unless value.is_a?(String) && LIST_STATUSES.include?(value)
          raise Error.new("status" => [ "is invalid" ])
        end

        value
      end

      def self.course_create(raw)
        raw = stringify(raw)
        reject_unknown!(raw, COURSE_CREATE_FIELDS)
        attrs = course_attrs(raw, required_name: true)
        reject_unordered_dates!(attrs["active_from"], attrs["active_until"])
        attrs
      end

      def self.course_patch(raw)
        raw = stringify(raw)
        reject_empty!(raw)
        reject_unknown!(raw, COURSE_PATCH_FIELDS)
        lock_version = require_lock_version!(raw)
        attrs = course_attrs(raw, required_name: raw.key?("name"))
        attrs["archived"] = optional_boolean!(raw, "archived") if raw.key?("archived")
        raise Error.new("base" => [ "can't be blank" ]) if attrs.empty?

        reject_unordered_dates!(attrs["active_from"], attrs["active_until"]) if attrs.key?("active_from") && attrs.key?("active_until")
        attrs.merge("lock_version" => lock_version)
      end

      def self.require_only_lock_version(raw)
        raw = stringify(raw)
        reject_empty!(raw)
        reject_unknown!(raw, LOCK_VERSION_FIELDS)
        require_lock_version!(raw)
      end

      def self.obligation_create(raw)
        raw = stringify(raw)
        reject_unknown!(raw, OBLIGATION_CREATE_FIELDS)
        kind = require_kind!(raw)
        attrs = obligation_attrs(raw, required_title: true)
        attrs["kind"] = kind
        apply_timing!(raw, kind: kind, attrs: attrs)
        attrs
      end

      def self.obligation_patch(raw, kind:)
        raw = stringify(raw)
        reject_empty!(raw)
        reject_unknown!(raw, OBLIGATION_PATCH_FIELDS)
        lock_version = require_lock_version!(raw)
        attrs = obligation_attrs(raw, required_title: raw.key?("title"))
        if raw.key?("status")
          value = raw["status"]
          unless value.is_a?(String) && OBLIGATION_STATUSES.include?(value)
            raise Error.new("status" => [ "is invalid" ])
          end

          attrs["status"] = value
        end
        apply_timing!(raw, kind: kind, attrs: attrs)
        raise Error.new("base" => [ "can't be blank" ]) if attrs.empty?

        attrs.merge("lock_version" => lock_version)
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

      def self.require_named_time_zone!(value)
        if value.nil? || (value.is_a?(String) && value.blank?)
          raise Error.new("time_zone" => [ "can't be blank" ])
        end
        unless value.is_a?(String)
          raise Error.new("time_zone" => [ "is invalid" ])
        end
        raise Error.new("time_zone" => [ "is invalid" ]) if ActiveSupport::TimeZone[value].nil?

        value
      end
      private_class_method :require_named_time_zone!

      def self.require_nonblank!(raw, key)
        value = raw[key]
        if !value.is_a?(String) || value.strip.empty?
          raise Error.new(key => [ "can't be blank" ])
        end

        value
      end
      private_class_method :require_nonblank!

      def self.require_kind!(raw)
        value = raw["kind"]
        if !value.is_a?(String) || value.strip.empty?
          raise Error.new("kind" => [ "can't be blank" ])
        end
        unless KINDS.include?(value)
          raise Error.new("kind" => [ "is invalid" ])
        end

        value
      end
      private_class_method :require_kind!

      def self.require_lock_version!(raw)
        unless raw.key?("lock_version")
          raise Error.new("lock_version" => [ "can't be blank" ])
        end

        value = raw["lock_version"]
        unless value.is_a?(Integer) && value >= 0
          raise Error.new("lock_version" => [ "is invalid" ])
        end

        value
      end
      private_class_method :require_lock_version!

      def self.course_attrs(raw, required_name:)
        attrs = {}
        attrs["name"] = require_nonblank!(raw, "name") if required_name
        attrs["code"] = optional_text!(raw, "code") if raw.key?("code")
        attrs["term_label"] = optional_text!(raw, "term_label") if raw.key?("term_label")
        attrs["colour"] = optional_colour!(raw) if raw.key?("colour")
        attrs["active_from"] = optional_calendar_date!(raw, "active_from") if raw.key?("active_from")
        attrs["active_until"] = optional_calendar_date!(raw, "active_until") if raw.key?("active_until")
        attrs
      end
      private_class_method :course_attrs

      def self.obligation_attrs(raw, required_title:)
        attrs = {}
        attrs["title"] = require_nonblank!(raw, "title") if required_title
        attrs["importance"] = optional_enum!(raw, "importance", IMPORTANCES) if raw.key?("importance")
        attrs["estimated_minutes"] = optional_positive_int!(raw, "estimated_minutes") if raw.key?("estimated_minutes")
        attrs["progress_percent"] = optional_progress!(raw) if raw.key?("progress_percent")
        attrs["notes"] = optional_text!(raw, "notes") if raw.key?("notes")
        attrs
      end
      private_class_method :obligation_attrs

      def self.optional_colour!(raw)
        value = raw["colour"]
        return if value.nil?
        unless value.is_a?(String) && value.match?(COLOUR)
          raise Error.new("colour" => [ "is invalid" ])
        end

        value
      end
      private_class_method :optional_colour!

      def self.optional_calendar_date!(raw, key)
        value = raw[key]
        return if value.nil?

        parsed = parse_calendar_date(value)
        raise Error.new(key => [ "is invalid" ]) if parsed.nil?

        parsed
      end
      private_class_method :optional_calendar_date!

      def self.parse_calendar_date(value)
        return unless value.is_a?(String) && value.match?(DATE)

        Date.iso8601(value)
      rescue ArgumentError
        nil
      end
      private_class_method :parse_calendar_date

      def self.parse_offset_time(value)
        return unless value.is_a?(String) && value.match?(OFFSET_TIME)

        Date.iso8601(value[0, 10])
        Time.iso8601(value)
      rescue ArgumentError
        nil
      end
      private_class_method :parse_offset_time

      def self.optional_offset_time!(raw, key)
        value = raw[key]
        return if value.nil?

        parsed = parse_offset_time(value)
        raise Error.new(key => [ "is invalid" ]) if parsed.nil?

        parsed
      end
      private_class_method :optional_offset_time!

      def self.optional_enum!(raw, key, allowed)
        value = raw[key]
        return if value.nil?
        unless value.is_a?(String) && allowed.include?(value)
          raise Error.new(key => [ "is invalid" ])
        end

        value
      end
      private_class_method :optional_enum!

      def self.optional_positive_int!(raw, key)
        value = raw[key]
        return if value.nil?
        unless value.is_a?(Integer) && value.positive?
          raise Error.new(key => [ "is invalid" ])
        end

        value
      end
      private_class_method :optional_positive_int!

      def self.optional_progress!(raw)
        value = raw["progress_percent"]
        return if value.nil?
        unless value.is_a?(Integer) && value.between?(0, 100)
          raise Error.new("progress_percent" => [ "is invalid" ])
        end

        value
      end
      private_class_method :optional_progress!

      def self.reject_unordered_dates!(from, to)
        return if from.nil? || to.nil?
        return if from <= to

        raise Error.new("active_until" => [ "is invalid" ])
      end
      private_class_method :reject_unordered_dates!

      def self.reject_disallowed_keys!(raw, keys)
        present = keys.select { |key| raw.key?(key) }
        raise Error.new(present.index_with { [ "is invalid" ] }) if present.any?
      end
      private_class_method :reject_disallowed_keys!

      def self.apply_interval!(raw, attrs)
        has_start = raw.key?("starts_at")
        has_end = raw.key?("ends_at")
        if has_start ^ has_end
          missing = has_start ? "ends_at" : "starts_at"
          raise Error.new(missing => [ "can't be blank" ])
        end
        return unless has_start

        starts_at = optional_offset_time!(raw, "starts_at")
        ends_at = optional_offset_time!(raw, "ends_at")
        if starts_at.nil? ^ ends_at.nil?
          raise Error.new("ends_at" => [ "is invalid" ])
        end
        raise Error.new("ends_at" => [ "is invalid" ]) if starts_at && ends_at && ends_at <= starts_at

        attrs["starts_at"] = starts_at
        attrs["ends_at"] = ends_at
      end
      private_class_method :apply_interval!

      def self.apply_timing!(raw, kind:, attrs:)
        case kind
        when "assignment"
          reject_disallowed_keys!(raw, %w[starts_at ends_at])
          attrs["due_at"] = optional_offset_time!(raw, "due_at") if raw.key?("due_at")
        when "exam"
          reject_disallowed_keys!(raw, %w[due_at])
          apply_interval!(raw, attrs)
        when "study_task"
          attrs["due_at"] = optional_offset_time!(raw, "due_at") if raw.key?("due_at")
          apply_interval!(raw, attrs)
          due_at = attrs["due_at"]
          ends_at = attrs["ends_at"]
          raise Error.new("ends_at" => [ "is invalid" ]) if due_at && ends_at && ends_at > due_at
        end
      end
      private_class_method :apply_timing!
    end
  end
end
