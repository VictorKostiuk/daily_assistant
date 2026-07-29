module Integrations
  module OpenRouter
    class ParseEvent
      class UnparseableResponse < StandardError; end

      Event = Struct.new(:title, :description, :location, :starts_at, :ends_at, :all_day, keyword_init: true)

      DEFAULT_DURATION = 1.hour
      DEFAULT_TITLE = "Untitled event".freeze

      def self.call(text:, time_zone:)
        new(text: text, time_zone: time_zone).call
      end

      def initialize(text:, time_zone:)
        @text = text
        @time_zone = time_zone
      end

      def call
        Time.use_zone(time_zone) do
          build(parse(Client.new.chat(system: system_prompt, user: text)))
        end
      end

      private

      attr_reader :text, :time_zone

      def system_prompt
        now = Time.zone.now

        <<~PROMPT
          You turn a short description into Google Calendar event parameters.
          The user's time zone is #{time_zone}. The current local time is #{now.strftime('%Y-%m-%dT%H:%M:%S')} (#{now.strftime('%A')}).

          Answer with a single JSON object and nothing else, using exactly these keys:
          {"title": string, "description": string or null, "location": string or null,
           "start_time": "YYYY-MM-DDTHH:MM:SS", "end_time": "YYYY-MM-DDTHH:MM:SS", "all_day": boolean}

          Rules:
          - Resolve relative dates such as "tomorrow" or "next friday" against the current local time.
          - Both times are local wall clock. Never append a UTC offset or a "Z" suffix.
          - When no end is given, make the event last one hour.
          - For an all-day event set all_day to true, use 00:00:00 for both times, and make end_time the last day the event covers.
          - Keep the title short and put any extra detail in description.
        PROMPT
      end

      def parse(content)
        json = content.to_s[/\{.*\}/m]
        raise UnparseableResponse, "no JSON object in response: #{content.to_s.truncate(200)}" if json.blank?

        JSON.parse(json)
      rescue JSON::ParserError => error
        raise UnparseableResponse, error.message
      end

      def build(payload)
        starts_at = time_from(payload["start_time"])
        raise UnparseableResponse, "no usable start time in #{payload.inspect}" if starts_at.blank?

        ends_at = time_from(payload["end_time"])
        ends_at = starts_at + DEFAULT_DURATION if ends_at.blank? || ends_at <= starts_at

        Event.new(
          title: payload["title"].presence || DEFAULT_TITLE,
          description: payload["description"].presence,
          location: payload["location"].presence,
          starts_at: starts_at,
          ends_at: ends_at,
          all_day: payload["all_day"] == true
        )
      end

      def time_from(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
