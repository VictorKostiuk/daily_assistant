module Integrations
  module Telegram
    class ConnectionLink
      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        return if bot_username.blank?

        token = ConnectionToken.issue!(user: user, purpose: ConnectionToken::TELEGRAM)

        "https://t.me/#{bot_username}?start=#{token}"
      end

      private

      attr_reader :user

      def bot_username
        @bot_username ||= Integrations::Telegram.bot_username
      end
    end
  end
end
