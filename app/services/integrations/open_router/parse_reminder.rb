module Integrations
  module OpenRouter
    class ParseReminder
      include EventParsing

      Result = Struct.new(:kind, :title, :scheduled_at, :event_id, :offset_minutes, keyword_init: true)

      MAX_OFFSET_MINUTES = 30.days.in_minutes.to_i

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
          build(parse_json(Client.new.chat(system: system_prompt, user: text)))
        end
      end

      private

      attr_reader :text, :time_zone, :candidates

      def system_prompt
        now = Time.zone.now

        <<~PROMPT
          You turn a reminder request into structured parameters.
          The user's time zone is #{time_zone}. The current local time is #{now.strftime('%Y-%m-%dT%H:%M:%S')} (#{now.strftime('%A')}).

          The user's upcoming calendar events, each with an id:
          #{candidates_json}

          Answer with a single JSON object and nothing else, using exactly these keys:
          {"kind": "event" or "standalone", "title": string,
           "scheduled_at": "YYYY-MM-DDTHH:MM:SS" or null, "event_id": string or null, "offset_minutes": integer or null}

          Rules:
          - Use "event" when the request is about being reminded before or at one of the listed events. Set event_id to that event's id and offset_minutes to how many minutes before its start time the reminder should fire (0 means at the event's start time). Leave scheduled_at null.
          - Use "standalone" for anything else: a specific date/time and something to be reminded of. Resolve relative dates such as "tomorrow" or "in 2 hours" against the current local time, and set scheduled_at to that local wall-clock time. Never append a UTC offset or a "Z" suffix. Leave event_id and offset_minutes null.
          - If the request clearly means "event" but none of the listed events plausibly match, still answer "event" with event_id null so the caller can report no match.
          - title is a short label for what the reminder is about.
        PROMPT
      end

      def build(payload)
        kind = payload["kind"].to_s
        raise EventParsing::UnparseableResponse, "unknown kind in #{payload.inspect}" unless %w[event standalone].include?(kind)

        scheduled_at = kind == "standalone" ? time_from(payload["scheduled_at"]) : nil
        raise EventParsing::UnparseableResponse, "no usable scheduled_at in #{payload.inspect}" if kind == "standalone" && scheduled_at.blank?

        Result.new(
          kind: kind,
          title: payload["title"].presence || "Reminder",
          scheduled_at: scheduled_at,
          event_id: kind == "event" ? payload["event_id"].to_s.presence : nil,
          offset_minutes: kind == "event" ? payload["offset_minutes"].to_i.clamp(0, MAX_OFFSET_MINUTES) : nil
        )
      end
    end
  end
end
