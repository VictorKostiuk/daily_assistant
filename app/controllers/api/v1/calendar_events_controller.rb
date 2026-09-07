module Api
  module V1
    class CalendarEventsController < BaseController
      EVENT_FIELDS = %w[title description location starts_at ends_at all_day].freeze

      rescue_from Integrations::Google::Client::NotConnected, with: :render_integration_not_connected
      rescue_from Integrations::Google::Client::ScopeMissing, with: :render_integration_not_connected
      rescue_from Signet::AuthorizationError, with: :render_integration_not_connected
      rescue_from Google::Apis::Error, with: :render_google_error
      rescue_from Integrations::Google::LocalCalendarEvent::PersistenceError, with: :render_local_save_failed

      def index
        InputValidator.time_range(request.query_parameters)
        return unless google_ready?

        result = Integrations::Google::ListEvents.call(
          user: current_api_user,
          time_min: request.query_parameters["from"] || request.query_parameters[:from],
          time_max: request.query_parameters["to"] || request.query_parameters[:to],
          page_token: request.query_parameters["page_token"] || request.query_parameters[:page_token]
        )
        render json: {
          items: result.events.map { |event| event_json(event) },
          next_page_token: result.next_page_token
        }
      end

      def create
        attrs = InputValidator.calendar_create(request.request_parameters, time_zone: caller_time_zone)
        return unless google_ready?

        created = Integrations::Google::CreateEvent.call(
          user: current_api_user,
          event: core_event_from(attrs),
          metadata: attrs["metadata"]
        )
        render json: event_json(created), status: :created
      end

      def update
        attrs = InputValidator.calendar_patch(request.request_parameters, time_zone: caller_time_zone)
        return unless google_ready?

        if event_fields?(attrs)
          updated = Integrations::Google::UpdateEvent.call(
            user: current_api_user,
            event_id: params[:id],
            sparse_attrs: attrs.slice(*EVENT_FIELDS),
            metadata: attrs["metadata"]
          )
          render json: event_json(updated)
        else
          annotate_only(attrs)
        end
      end

      def destroy
        return unless google_ready?

        Integrations::Google::CancelEvent.call(user: current_api_user, event_id: params[:id])
        head :no_content
      end

      private

      def annotate_only(attrs)
        google_event = google_client.calendar.get_event(calendar_id, params[:id])
        Integrations::Google::LocalCalendarEvent.sync(
          user: current_api_user,
          external_event_id: google_event.id,
          external_calendar_id: calendar_id,
          event: Integrations::Google::EventPayload.from_provider(google_event, time_zone: caller_time_zone),
          time_zone: caller_time_zone,
          metadata: attrs["metadata"]
        )
        render json: event_json(google_event)
      rescue Integrations::Google::LocalCalendarEvent::PersistenceError
        render_internal_error
      end

      def google_ready?
        return true if current_api_user.google_integration&.connected?

        render_integration_not_connected
        false
      end

      def google_client
        @google_client ||= Integrations::Google::Client.new(current_api_user.google_integration)
      end

      def calendar_id
        current_api_user.user_setting&.default_calendar_id.presence || Integrations::Google::CreateEvent::DEFAULT_CALENDAR_ID
      end

      def event_fields?(attrs)
        EVENT_FIELDS.any? { |field| attrs.key?(field) }
      end

      def core_event_from(attrs)
        Integrations::OpenRouter::EventParsing::Event.new(
          title: attrs["title"],
          description: attrs["description"],
          location: attrs["location"],
          starts_at: attrs["starts_at"],
          ends_at: attrs["ends_at"],
          all_day: attrs["all_day"]
        )
      end

      def event_json(google_event)
        core = Integrations::Google::EventPayload.from_provider(google_event, time_zone: caller_time_zone)
        record = current_api_user.calendar_events.find_by(
          provider: "google",
          external_calendar_id: calendar_id,
          external_event_id: google_event.id
        )
        source = SourceMetadata.load(record&.metadata)
        {
          id: google_event.id,
          title: core.title,
          description: core.description,
          location: core.location,
          starts_at: format_time(core.starts_at, core.all_day),
          ends_at: format_time(core.ends_at, core.all_day),
          all_day: core.all_day,
          time_zone: caller_time_zone,
          context_type: source["context_type"],
          source_app: source["source_app"],
          source_entity_type: source["source_entity_type"],
          source_entity_id: source["source_entity_id"]
        }
      end

      def format_time(time, all_day)
        return if time.nil?

        if all_day
          time.in_time_zone(caller_time_zone).to_date.iso8601
        else
          time.iso8601
        end
      end

      def render_google_error(error)
        status = error.respond_to?(:status_code) ? error.status_code.to_i : nil
        return render_not_found if status == 404 && %w[update destroy].include?(action_name)
        return render_validation_error("page_token" => [ "is invalid" ]) if invalid_page_token?(error)

        render_provider_error
      end

      def invalid_page_token?(error)
        return false unless error.is_a?(Google::Apis::ClientError) && error.status_code.to_i == 400

        [ error.message, error.body ].compact.join(" ").match?(/page token/i)
      end
    end
  end
end
