module Integrations
  module OpenRouter
    class ParseEventCancellation
      include EventParsing

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
          parse_json(Client.new.chat(system: system_prompt, user: text))["event_id"].presence
        end
      end

      private

      attr_reader :text, :time_zone, :candidates

      def system_prompt
        now = Time.zone.now

        <<~PROMPT
          You match an instruction to one event in a list of the user's upcoming Google Calendar events.
          The user's time zone is #{time_zone}. The current local time is #{now.strftime('%Y-%m-%dT%H:%M:%S')} (#{now.strftime('%A')}).

          The user's upcoming events:
          #{candidates_json}

          Answer with a single JSON object and nothing else, using exactly this key:
          {"event_id": string or null}

          Rules:
          - Set event_id to the id of the single event from the list the instruction is most clearly about cancelling.
          - If no event in the list plausibly matches, set event_id to null.
        PROMPT
      end
    end
  end
end
