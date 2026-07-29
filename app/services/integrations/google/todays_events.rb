module Integrations
  module Google
    class TodaysEvents
      Entry = Struct.new(:title, :starts_at, :all_day, keyword_init: true)

      DEFAULT_CALENDAR_ID = "primary".freeze
      MAX_RESULTS = 50

      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        Time.use_zone(time_zone) do
          events.reject { |event| event.status == "cancelled" }.map { |event| entry_for(event) }
        end
      end

      private

      attr_reader :user

      def events
        client.calendar.list_events(
          calendar_id,
          single_events: true,
          order_by: "startTime",
          time_min: Time.zone.now.beginning_of_day.iso8601,
          time_max: Time.zone.now.end_of_day.iso8601,
          time_zone: time_zone,
          max_results: MAX_RESULTS
        ).items.to_a
      end

      def entry_for(event)
        starts_at = event.start&.date_time

        Entry.new(
          title: event.summary.to_s.strip,
          starts_at: starts_at&.in_time_zone,
          all_day: starts_at.nil?
        )
      end

      def client
        @client ||= Integrations::Google::Client.new(user.google_integration)
      end

      def calendar_id
        user.user_setting&.default_calendar_id.presence || DEFAULT_CALENDAR_ID
      end

      def time_zone
        @time_zone ||= user.time_zone.presence || Time.zone.name
      end
    end
  end
end
