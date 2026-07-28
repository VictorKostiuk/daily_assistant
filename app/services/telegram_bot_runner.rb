class TelegramBotRunner
  def self.start
    new.start
  end

  def initialize(token: ENV.fetch("TELEGRAM_BOT_TOKEN"), logger: nil)
    @token = token
    @logger = logger || ActiveSupport::TaggedLogging.logger($stdout)
  end

  def start
    @bot = Telegram::Bot::Client.new(@token)
    Rails.application.config.telegram_bot = @bot

    trap_shutdown_signals
    @bot.api.delete_webhook

    log "Telegram bot polling started"

    @bot.listen do |message|
      handle(message)
    rescue StandardError => e
      log "Telegram bot message failed: #{e.class}: #{e.message}"
    end
  rescue Telegram::Bot::Exceptions::ResponseError => e
    log "Telegram bot API failed: #{e.class}: #{e.message}"
    @bot&.stop
    raise
  ensure
    Rails.application.config.telegram_bot = nil
    log "Telegram bot polling stopped" if @bot
  end

  private

  def trap_shutdown_signals
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        @bot&.stop
      end
    end
  end

  def log(message)
    @logger.info(message)
    $stdout.flush
  end

  def handle(message)
    return unless message.respond_to?(:text)

    case message.text
    when "/start"
      send_message(message, I18n.t("telegram_bot.start", name: sender_name(message), chat_id: message.chat.id))
    when "/stop"
      send_message(message, I18n.t("telegram_bot.stop", name: sender_name(message), chat_id: message.chat.id))
    end
  end

  def send_message(message, text)
    @bot.api.send_message(chat_id: message.chat.id, text: text)
  end

  def sender_name(message)
    message.from&.first_name.presence || I18n.t("telegram_bot.fallback_name")
  end
end
