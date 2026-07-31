class ProcessTelegramUpdateJob < ApplicationJob
  queue_as :default

  def perform(update_class_name, update_attributes)
    update = update_class_name.constantize.new(update_attributes)

    TelegramBot::Router.new(bot: telegram_bot, logger: Rails.logger).call(update)
  rescue StandardError => error
    Rails.logger.error("[telegram_bot] update failed: #{error.class}: #{error.message}")
    raise
  end

  private

  def telegram_bot
    @telegram_bot ||= Telegram::Bot::Client.new(ENV.fetch("TELEGRAM_BOT_TOKEN"))
  end
end
