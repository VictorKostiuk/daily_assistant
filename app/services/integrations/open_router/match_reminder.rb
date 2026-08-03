module Integrations
  module OpenRouter
    class MatchReminder
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
          parse_json(Client.new.chat(system: system_prompt, user: text))["reminder_id"].to_s.presence
        end
      end

      private

      attr_reader :text, :time_zone, :candidates

      def system_prompt
        now = Time.zone.now

        <<~PROMPT
          You match an instruction to one of the user's pending reminders.
          The current local time is #{now.strftime('%Y-%m-%dT%H:%M:%S')} (#{now.strftime('%A')}).

          The user's pending reminders:
          #{candidates_json}

          Answer with a single JSON object and nothing else, using exactly this key:
          {"reminder_id": string or null}

          Rules:
          - Set reminder_id to the id of the single reminder from the list the instruction is most clearly about.
          - If no reminder in the list plausibly matches, set reminder_id to null.
        PROMPT
      end

      def candidates_json
        candidates.map { |candidate|
          {
            id: candidate.id,
            title: candidate.title,
            scheduled_at: candidate.scheduled_at&.strftime("%Y-%m-%dT%H:%M:%S")
          }.compact
        }.to_json
      end
    end
  end
end
