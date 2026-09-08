module Api
  module V1
    class IntegrationsController < BaseController
      skip_before_action :authenticate_api_user!, only: :connect_google_preflight
      prepend_before_action :reject_disallowed_google_connect_origin,
                            only: %i[connect_google connect_google_preflight]

      # Status JSON, allowlisted and documented:
      #   google.connected           — true iff user.google_integration&.connected?
      #   google.reconnect_required  — true iff user.google_integration&.reconnect_required?
      #                                (false when no row)
      #   telegram.connected         — true iff user.telegram_account is present
      # Missing rows do not create IntegrationProvider or UserIntegration records.
      def index
        google = current_api_user.google_integration
        render json: {
          google: {
            connected: google&.connected? || false,
            reconnect_required: google&.reconnect_required? || false
          },
          telegram: {
            connected: current_api_user.telegram_account.present?
          }
        }
      end

      def connect_telegram
        url = Integrations::Telegram::ConnectionLink.call(user: current_api_user)
        if url.blank?
          return render_error(
            code: "integration_unavailable",
            message: "Integration is unavailable",
            status: :service_unavailable
          )
        end

        render json: { url: url }
      end

      def disconnect_telegram
        current_api_user.telegram_account&.destroy!
        head :no_content
      end

      # Browser-only initiation. The SPA must call this with credentials:
      # "include" so the session cookie is stored. The initiating origin must
      # be same-site with Core; APP_URL (the pinned OmniAuth callback) must
      # resolve to the same host that sets this cookie.
      def connect_google
        unless google_configured?
          return render_error(
            code: "integration_unavailable",
            message: "Integration is unavailable",
            status: :service_unavailable
          )
        end

        token = ConnectionToken.issue!(user: current_api_user, purpose: ConnectionToken::GOOGLE)
        Integrations::Google::ConnectIntent.store(session, user: current_api_user, token: token)
        render json: { url: google_oauth_connect_url(token: token) }
      end

      def connect_google_preflight
        head :no_content
      end

      def disconnect_google
        Integrations::Google::DisconnectAccount.call(user: current_api_user)
        head :no_content
      end

      private

      def reject_disallowed_google_connect_origin
        origin = request.origin
        response.set_header("Vary", "Origin")

        if google_connect_origin_allowed?(origin)
          apply_google_connect_cors_headers
          return
        end

        render_error(
          code: "origin_not_allowed",
          message: "Origin is not allowed",
          status: :forbidden
        )
      end

      def google_connect_origin_allowed?(origin)
        return true if origin.blank?
        return true if origin == request.base_url

        origin.start_with?("https://") && google_connect_allowed_origins.include?(origin)
      end

      def google_connect_allowed_origins
        ENV.fetch("GOOGLE_CONNECT_ORIGINS", "").split(",").map(&:strip).reject(&:blank?)
      end

      def apply_google_connect_cors_headers
        origin = request.origin
        return if origin.blank? || origin == request.base_url
        return unless google_connect_origin_allowed?(origin)

        response.set_header("Access-Control-Allow-Origin", origin)
        response.set_header("Access-Control-Allow-Credentials", "true")
        response.set_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        response.set_header("Vary", "Origin")
      end

      def google_configured?
        settings = Integrations::Google.settings
        settings.client_id.present? && settings.client_secret.present?
      end
    end
  end
end
