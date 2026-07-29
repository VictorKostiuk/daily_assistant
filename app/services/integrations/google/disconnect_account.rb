require "net/http"

module Integrations
  module Google
    class DisconnectAccount
      REVOKE_URL = "https://oauth2.googleapis.com/revoke".freeze
      TIMEOUT_SECONDS = 5

      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        return if integration.blank?

        revoke_remote_grant

        integration.update!(
          status: :revoked,
          access_token: nil,
          refresh_token: nil,
          token_expires_at: nil,
          scopes: [],
          connected_at: nil,
          last_error_at: nil,
          last_error_message: nil
        )
        integration
      end

      private

      attr_reader :user

      def integration
        @integration ||= user.google_integration
      end

      def revoke_remote_grant
        token = integration.refresh_token.presence || integration.access_token.presence
        return if token.blank?

        uri = URI(REVOKE_URL)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(token: token)

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: true,
          open_timeout: TIMEOUT_SECONDS,
          read_timeout: TIMEOUT_SECONDS
        ) { |http| http.request(request) }
      rescue StandardError => error
        Rails.logger.warn("[integrations.google] revoke request failed: #{error.class}")
      end
    end
  end
end
