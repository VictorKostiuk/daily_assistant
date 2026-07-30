module Integrations
  module OpenRouter
    module EventParsing
      class UnparseableResponse < StandardError; end

      Event = Struct.new(:title, :description, :location, :starts_at, :ends_at, :all_day, keyword_init: true)

      DEFAULT_DURATION = 1.hour
      DEFAULT_TITLE = "Untitled event".freeze

      private

      def parse_json(content)
        json = content.to_s[/\{.*\}/m]
        raise UnparseableResponse, "no JSON object in response: #{content.to_s.truncate(200)}" if json.blank?

        JSON.parse(json)
      rescue JSON::ParserError => error
        raise UnparseableResponse, error.message
      end

      def event_from(payload)
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

      def candidates_json
        candidates.map do |candidate|
          {
            id: candidate.id,
            title: candidate.title,
            location: candidate.location,
            all_day: candidate.all_day,
            start_time: candidate.all_day ? candidate.starts_at&.to_date&.iso8601 : candidate.starts_at&.strftime("%Y-%m-%dT%H:%M:%S")
          }.compact
        end.to_json
      end
    end
  end
end
