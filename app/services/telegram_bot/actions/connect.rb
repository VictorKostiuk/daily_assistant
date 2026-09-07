module TelegramBot
  module Actions
    class Connect < Base
      def call
        send_message(t("commands.connect.message"))
      end
    end
  end
end
