module DailyDigests
  class Deliver
    def self.call(digest)
      new(digest).call
    end

    def initialize(digest)
      @digest = digest
    end

    def call
      return if digest.next_delivery_at.blank? || digest.next_delivery_at > Time.current

      result = Generate.call(digest)
      send_message(result.text) if !result.empty || digest.send_when_empty?

      digest.update!(last_sent_at: Time.current, next_delivery_at: CalculateNextDelivery.call(digest))
    end

    private

    attr_reader :digest

    def send_message(text)
      return unless Array(digest.channels).include?("telegram")

      telegram_account = digest.user.telegram_account
      return if telegram_account.blank?

      bot = Telegram::Bot::Client.new(ENV.fetch("TELEGRAM_BOT_TOKEN"))
      bot.api.send_message(chat_id: telegram_account.telegram_chat_id, text: text)
    end
  end
end
