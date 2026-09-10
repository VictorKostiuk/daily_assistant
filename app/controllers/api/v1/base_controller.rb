module Api
  module V1
    class BaseController < ActionController::API
      wrap_parameters false
      before_action :authenticate_api_user!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::StaleObjectError, with: :render_conflict
      rescue_from SourceMetadata::Invalid, with: :render_source_metadata_invalid
      rescue_from Api::V1::InputValidator::Error, with: :render_input_invalid

      private

      attr_reader :current_api_user, :current_api_token

      def authenticate_api_user!
        api_token = ApiToken.find_usable(bearer_token)
        user = api_token&.user
        return render_unauthorized unless user&.active?

        api_token.update_column(:last_used_at, Time.current)
        @current_api_token = api_token
        @current_api_user = user
      end

      def bearer_token
        header = request.headers["Authorization"]
        return if header.blank?

        scheme, value = header.split(/ +/, 2)
        return unless scheme&.casecmp("Bearer")&.zero?
        return if value.blank? || value.match?(/\s/)

        value
      end

      def render_unauthorized
        render_error(code: "unauthorized", message: "Unauthorized", status: :unauthorized)
      end

      def render_not_found(_exception = nil)
        render_error(code: "not_found", message: "Not found", status: :not_found)
      end

      def render_error(code:, message:, status:, details: {})
        render json: { error: { code: code, message: message, details: details } }, status: status
      end

      def render_validation_error(details)
        render_error(code: "validation_error", message: "Request is invalid", details: details, status: :unprocessable_content)
      end

      def render_source_metadata_invalid(error)
        render_validation_error(error.details)
      end

      def render_input_invalid(error)
        render_validation_error(error.details)
      end

      def render_conflict
        render_error(code: "conflict", message: "Conflict", status: :conflict)
      end

      def render_integration_not_connected
        render_error(code: "integration_not_connected", message: "Google is not connected", status: :conflict)
      end

      def render_provider_error
        render_error(code: "provider_error", message: "Provider request failed", status: :bad_gateway)
      end

      def render_integration_unavailable
        render_error(code: "integration_unavailable", message: "Integration is unavailable", status: :service_unavailable)
      end

      def render_local_save_failed(error)
        render_error(
          code: "local_save_failed",
          message: "The change was saved with the provider but the local record could not be updated",
          details: { "provider_event_id" => error.provider_event_id },
          status: :bad_gateway
        )
      end

      def render_internal_error
        render_error(code: "internal_error", message: "Request failed", status: :internal_server_error)
      end

      def caller_time_zone
        current_api_user.time_zone.presence || Time.zone.name
      end
    end
  end
end
