module TelegramBot
  class Runner
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

      @bot.listen do |update|
        ProcessTelegramUpdateJob.perform_later(update.class.name, UpdateSerializer.dump(update))
      rescue StandardError => e
        log "Telegram bot failed to enqueue update: #{e.class}: #{e.message}"
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
  end
end
