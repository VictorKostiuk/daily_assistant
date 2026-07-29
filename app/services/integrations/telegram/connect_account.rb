module Integrations
  module Telegram
    class ConnectAccount
      Result = Struct.new(:status, :user, keyword_init: true)

      def self.call(token:, telegram_user:, chat_id:)
        new(token: token, telegram_user: telegram_user, chat_id: chat_id).call
      end

      def initialize(token:, telegram_user:, chat_id:)
        @token = token
        @telegram_user = telegram_user
        @chat_id = chat_id
      end

      def call
        return Result.new(status: :invalid_token) if user.blank?
        return Result.new(status: :taken) if linked_elsewhere?

        account.assign_attributes(attributes)
        account.save!

        Result.new(status: :connected, user: user)
      end

      private

      attr_reader :token, :telegram_user, :chat_id

      def user
        return @user if defined?(@user)

        @user = ConnectionToken.claim(token, purpose: ConnectionToken::TELEGRAM)
      end

      def existing_account
        return @existing_account if defined?(@existing_account)

        @existing_account = TelegramAccount.find_by(telegram_user_id: telegram_user.id)
      end

      def linked_elsewhere?
        existing_account.present? && existing_account.user_id != user.id
      end

      # Reuse the member's current row when they link a different Telegram account,
      # so a user never ends up with two.
      def account
        @account ||= existing_account || user.telegram_account || TelegramAccount.new
      end

      def attributes
        {
          user: user,
          telegram_user_id: telegram_user.id,
          telegram_chat_id: chat_id,
          username: telegram_user.username,
          first_name: telegram_user.first_name,
          last_name: telegram_user.last_name,
          language_code: telegram_user.language_code,
          bot_blocked: false,
          connected_at: account.connected_at || Time.current,
          last_interaction_at: Time.current
        }
      end
    end
  end
end
