require "uri"

module TelegramBot
  module Actions
    class Connect < Base
      LOCAL_CALLBACK_DATA = "connect.local_url"

      def call
        send_message(
          t("commands.connect.message"),
          reply_markup: connect_markup
        )
      end

      private

      def connect_markup
        Telegram::Bot::Types::InlineKeyboardMarkup.new(
          inline_keyboard: [ [ Telegram::Bot::Types::InlineKeyboardButton.new(
            text: t("commands.connect.button"), url: app_url, callback_data: LOCAL_CALLBACK_DATA) ] ]
        )
      end


      def app_url
        "https://google.com"
        # ENV.fetch("APP_URL", "http://localhost:3000")
      end
    end
  end
end
