module Integrations
  module OpenRouter
    class ParseEventUpdate
      include EventParsing

      Result = Struct.new(:event_id, :event, keyword_init: true)

      def self.call(text:, time_zone:, candidates:)
        new(text: text, time_zone: time_zone, candidates: candidates).call
      end

      def initialize(text:, time_zone:, candidates:)
        @text = text
        @time_zone = time_zone
        @candidates = candidates
      end

      def call
        Time.use_zone(time_zone) do
          payload = parse_json(Client.new.chat(system: system_prompt, user: text))

          if payload["event_id"].blank?
            Result.new(event_id: nil, event: nil)
          else
            Result.new(event_id: payload["event_id"], event: event_from(payload))
          end
        end
      end

      private

      attr_reader :text, :time_zone, :candidates

      def system_prompt
        now = Time.zone.now

        <<~PROMPT
          You match an instruction to one event in a list of the user's upcoming Google Calendar events, then work out that event's details after applying the instruction.
          The user's time zone is #{time_zone}. The current local time is #{now.strftime('%Y-%m-%dT%H:%M:%S')} (#{now.strftime('%A')}).

          The user's upcoming events:
          #{candidates_json}

          Answer with a single JSON object and nothing else, using exactly these keys:
          {"event_id": string or null, "title": string, "description": string or null, "location": string or null,
           "start_time": "YYYY-MM-DDTHH:MM:SS", "end_time": "YYYY-MM-DDTHH:MM:SS", "all_day": boolean}

          Rules:
          - Set event_id to the id of the single event from the list the instruction is most clearly about.
          - If no event in the list plausibly matches, set event_id to null and fill the other fields with reasonable placeholders (they will be ignored).
          - For every other field, start from that matched event's current values above and change only what the instruction asks to change.
          - Resolve relative dates such as "tomorrow" or "next friday" against the current local time.
          - Both times are local wall clock. Never append a UTC offset or a "Z" suffix.
          - For an all-day event set all_day to true, use 00:00:00 for both times, and make end_time the last day the event covers.
        PROMPT
      end
    end
  end
end
