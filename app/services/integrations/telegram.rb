module Integrations
  module Telegram
    def self.bot_username
      ENV["TELEGRAM_BOT_USERNAME"].to_s.delete_prefix("@").presence
    end
  end
end
