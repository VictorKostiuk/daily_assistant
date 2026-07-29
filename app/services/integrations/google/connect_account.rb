module Integrations
  module Google
    class ConnectAccount
      def self.call(user:, auth:)
        new(user: user, auth: auth).call
      end

      def initialize(user:, auth:)
        @user = user
        @auth = auth
      end

      def call
        integration.assign_attributes(attributes)
        integration.save!
        integration
      end

      private

      attr_reader :user, :auth

      def integration
        @integration ||= user.user_integrations.find_or_initialize_by(
          integration_provider: IntegrationProvider.google
        )
      end

      def attributes
        {
          status: :connected,
          access_token: credentials.token,
          # Google omits the refresh token outside the consent step, so keep the stored one.
          refresh_token: credentials.refresh_token.presence || integration.refresh_token,
          token_expires_at: token_expires_at,
          external_account_id: auth.uid,
          external_account_email: auth.info&.email,
          scopes: granted_scopes,
          connected_at: integration.connected_at || Time.current,
          last_error_at: nil,
          last_error_message: nil
        }
      end

      def credentials
        auth.credentials
      end

      def token_expires_at
        expires_at = credentials.expires_at
        return if expires_at.blank?

        Time.zone.at(expires_at.to_i)
      end

      def granted_scopes
        credentials.scope.to_s.split.presence || Integrations::Google.settings.scopes
      end
    end
  end
end
