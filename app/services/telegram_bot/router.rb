module TelegramBot
  class Router
    MESSAGE_ACTIONS = {
      "/start" => Actions::Start,
      "/connect" => Actions::Connect,
      "/stop" => Actions::Stop,
      "/todays_events" => Actions::TodaysEvents
    }.freeze

    CALLBACK_ACTIONS = {
      Actions::Connect::LOCAL_CALLBACK_DATA => Actions::Connect
    }.freeze

    def initialize(bot:, logger:)
      @bot = bot
      @logger = logger
    end

    def call(update)
      if update.is_a?(Telegram::Bot::Types::CallbackQuery)
        handle_callback(update)
      elsif update.respond_to?(:text)
        handle_message(update)
      end
    end

    private

    attr_reader :bot, :logger

    def handle_message(message)
      action_class = MESSAGE_ACTIONS[message.text.to_s.split.first]
      return unless action_class

      action_class.call(bot: bot, update: message)
    end

    def handle_callback(callback_query)
      action_class = CALLBACK_ACTIONS[callback_query.data]
      return unless action_class

      action_class.call_callback(bot: bot, update: callback_query)
    end
  end
end
