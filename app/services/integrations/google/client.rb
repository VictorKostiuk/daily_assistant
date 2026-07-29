module Integrations
  module Google
    class Client
      class NotConnected < StandardError; end
      class ScopeMissing < StandardError; end

      def initialize(integration)
        @integration = integration
      end

      def calendar
        service_for(::Google::Apis::CalendarV3::CalendarService, :calendar)
      end

      def authorization
        ensure_connected!
        refresh! if credentials.needs_access_token?
        credentials
      end

      private

      attr_reader :integration

      def service_for(service_class, service)
        ensure_connected!
        ensure_granted!(service)

        service_class.new.tap { |instance| instance.authorization = authorization }
      end

      def ensure_connected!
        raise NotConnected, "Google integration is not connected" unless integration&.connected?
      end

      def ensure_granted!(service)
        return if Integrations::Google.granted_services(integration.scopes).include?(service)

        raise ScopeMissing, "Google #{service} access was not granted"
      end

      def credentials
        @credentials ||= ::Google::Auth::UserRefreshCredentials.new(
          client_id: Integrations::Google.settings.client_id,
          client_secret: Integrations::Google.settings.client_secret,
          scope: integration.scopes,
          refresh_token: integration.refresh_token
        ).tap do |client|
          client.access_token = integration.access_token
          client.expires_at = integration.token_expires_at
        end
      end

      def refresh!
        credentials.fetch_access_token!

        integration.update!(
          access_token: credentials.access_token,
          token_expires_at: credentials.expires_at,
          status: :connected,
          last_error_at: nil,
          last_error_message: nil
        )
      rescue ::Signet::AuthorizationError => error
        integration.update!(
          status: :expired,
          last_error_at: Time.current,
          last_error_message: error.message
        )
        raise
      end
    end
  end
end
