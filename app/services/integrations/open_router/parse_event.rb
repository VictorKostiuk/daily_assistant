module Integrations
  module OpenRouter
    class ParseEvent
      include EventParsing

      def self.call(text:, time_zone:)
        new(text: text, time_zone: time_zone).call
      end

      def initialize(text:, time_zone:)
        @text = text
        @time_zone = time_zone
      end

      def call
        Time.use_zone(time_zone) do
          event_from(parse_json(Client.new.chat(system: system_prompt, user: text)))
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
    end
  end
end
