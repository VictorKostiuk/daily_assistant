module TelegramBot
  class PendingAction
    TTL = 10.minutes

    def self.set(telegram_user_id, **payload)
      return if telegram_user_id.blank?

      Rails.cache.write(key(telegram_user_id), payload, expires_in: TTL)
    end

    def self.take(telegram_user_id)
      return if telegram_user_id.blank?

      Rails.cache.read(key(telegram_user_id)).tap { |payload| clear(telegram_user_id) if payload }
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
