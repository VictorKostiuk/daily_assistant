module TelegramBot
  module Actions
    class Start < Base
      def call
        send_message(t("commands.start", name: sender_name, chat_id: chat_id))
      end
    end
  end
end
