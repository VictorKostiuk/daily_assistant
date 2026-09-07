module Integrations
  module Google
    # Raised from the OmniAuth setup: hook. fail! puts message_key into the
    # failure URL, so this message is generic on purpose.
    class ConnectAborted < StandardError
      def initialize
        super("invalid")
      end
    end

    # Browser transaction for Google connect. Stored in the existing Rails
    # session — not a second cookie. Devise current_user is never an identity
    # fallback; the bound bearer initiation is the intended account.
    class ConnectIntent
      SESSION_KEY = :google_connect

      def self.store(session, user:, token:)
        session[SESSION_KEY] = { "user_id" => user.id, "token" => token }
      end

      def self.clear(session)
        session.delete(SESSION_KEY)
      end

      def self.valid?(session:, token:)
        new(session).valid?(token)
      end

      def initialize(session)
        @session = session
      end

      def valid?(token)
        user.present? && user.active? && token_matches?(token) && claimable?(token)
      end

      def user
        return @user if defined?(@user)

        @user = User.find_by(id: payload["user_id"])
      end

      def raw_token
        payload["token"]
      end

      def clear
        self.class.clear(@session)
      end

      private

      def payload
        data = @session[SESSION_KEY]
        return {} if data.blank?

        data.respond_to?(:stringify_keys) ? data.stringify_keys : data
      end

      def token_matches?(token)
        return false if token.blank? || raw_token.blank?

        ActiveSupport::SecurityUtils.secure_compare(
          ConnectionToken.digest(token),
          ConnectionToken.digest(raw_token)
        )
      end

      def claimable?(token)
        record = ConnectionToken.find_by(
          token_digest: ConnectionToken.digest(token),
          purpose: ConnectionToken::GOOGLE
        )
        record.present? &&
          record.used_at.nil? &&
          record.expires_at > Time.current &&
          record.user_id == user.id
      end
    end
  end
end
