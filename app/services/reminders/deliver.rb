module Reminders
  class Deliver
    def self.call(reminder:)
      new(reminder: reminder).call
    end

    def initialize(reminder:)
      @reminder = reminder
    end

    def call
      send_telegram_message
      reminder.update!(status: :delivered, sent_at: Time.current)
    rescue StandardError => error
      reminder.update!(status: :failed, failed_at: Time.current, failure_message: error.message)
    end

    private

    attr_reader :reminder

    def send_telegram_message
      raise "reminder channels do not include telegram" unless Array(reminder.channels).include?("telegram")

      telegram_account = reminder.user.telegram_account
      raise "no telegram account linked" if telegram_account.blank?

      bot = Telegram::Bot::Client.new(ENV.fetch("TELEGRAM_BOT_TOKEN"))
      bot.api.send_message(chat_id: telegram_account.telegram_chat_id, text: message_text)
    end

    def message_text
      I18n.t("telegram_bot.reminders.deliver", title: reminder.title)
    end
  end
end
