module Integrations
  module Google
    class ListEvents
      DEFAULT_CALENDAR_ID = "primary".freeze
      PAGE_SIZE = 100

      Result = Struct.new(:events, :next_page_token, keyword_init: true)

      def self.call(user:, time_min:, time_max:, page_token: nil)
        new(user: user, time_min: time_min, time_max: time_max, page_token: page_token).call
      end

      def initialize(user:, time_min:, time_max:, page_token:)
        @user = user
        @time_min = time_min
        @time_max = time_max
        @page_token = page_token
      end

      def call
        response = client.calendar.list_events(
          calendar_id,
          single_events: true,
          order_by: "startTime",
          time_min: time_min,
          time_max: time_max,
          time_zone: time_zone,
          max_results: PAGE_SIZE,
          page_token: page_token.presence
        )

        Result.new(events: Array(response.items), next_page_token: response.next_page_token)
      end

      private

      attr_reader :user, :time_min, :time_max, :page_token

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
