module TelegramBot
  module Actions
    class Stop < Base
      def call
        send_message(t("commands.stop", name: sender_name, chat_id: chat_id))
      end
    end
  end
end
