module TelegramBot
  class PendingAction
    TTL = 10.minutes

    def self.set(telegram_user_id, command)
      return if telegram_user_id.blank?

      Rails.cache.write(key(telegram_user_id), command, expires_in: TTL)
    end

    def self.take(telegram_user_id)
      return if telegram_user_id.blank?

      Rails.cache.read(key(telegram_user_id)).tap { |command| clear(telegram_user_id) if command }
    end

    def self.clear(telegram_user_id)
      Rails.cache.delete(key(telegram_user_id))
    end

    def self.key(telegram_user_id)
      "telegram_bot/pending_action/#{telegram_user_id}"
    end
    private_class_method :key
  end
end
