module TelegramBot
  module Actions
    class Start < Base
      def call
        return send_message(t("commands.start.greeting", name: sender_name)) if connection_token.blank?

        result = Integrations::Telegram::ConnectAccount.call(
          token: connection_token,
          telegram_user: update.from,
          chat_id: chat_id
        )

        send_message(t("commands.start.#{result.status}", name: sender_name))
      end

      private

      def connection_token
        update.text.to_s.split[1]
      end
    end
  end
end
