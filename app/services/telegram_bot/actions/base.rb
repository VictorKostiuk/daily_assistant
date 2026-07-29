module TelegramBot
  module Actions
    class Base
      def self.call(bot:, update:)
        new(bot: bot, update: update).call
      end

      def self.call_callback(bot:, update:)
        new(bot: bot, update: update).call_callback
      end

      def initialize(bot:, update:)
        @bot = bot
        @update = update
      end

      def call
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      def call_callback
        call
      end

      private

      attr_reader :bot, :update

      def send_message(text, **options)
        bot.api.send_message({ chat_id: chat_id, text: text }.merge(options))
      end

      def answer_callback(text: nil)
        return unless update.is_a?(Telegram::Bot::Types::CallbackQuery)

        payload = { callback_query_id: update.id }
        payload[:text] = text if text.present?

        bot.api.answer_callback_query(payload)
      end

      def chat_id
        return update.chat.id if update.respond_to?(:chat) && update.chat
        return update.message.chat.id if update.respond_to?(:message) && update.message&.chat
        return update.from.id if update.respond_to?(:from) && update.from

        nil
      end

      def sender_name
        update.from&.first_name.presence || t("fallback_name")
      end

      def telegram_account
        return @telegram_account if defined?(@telegram_account)

        @telegram_account = TelegramAccount.find_by(telegram_user_id: update.from&.id)
      end

      def current_user
        telegram_account&.user
      end

      def t(key, **options)
        I18n.t("telegram_bot.#{key}", **options)
      end
    end
  end
end
