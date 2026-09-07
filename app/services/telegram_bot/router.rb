module TelegramBot
  class Router
    MESSAGE_ACTIONS = {
      "/start" => Actions::Start,
      "/connect" => Actions::Connect,
      "/stop" => Actions::Stop,
      "/todays_events" => Actions::TodaysEvents,
      "/setup_event" => Actions::SetupEvent,
      "/update_event" => Actions::UpdateEvent,
      "/cancel_event" => Actions::CancelEvent,
      "/remind" => Actions::RemindMe,
      "/reminders" => Actions::RemindersList,
      "/cancel_reminder" => Actions::CancelReminder,
      "/daily_digest" => Actions::DailyDigestSettings,
      "/reminder_preference" => Actions::ReminderPreferenceSettings
    }.freeze

    def initialize(bot:, logger:)
      @bot = bot
      @logger = logger
    end

    def call(update)
      return if update.is_a?(Telegram::Bot::Types::CallbackQuery)

      handle_message(update) if update.respond_to?(:text)
    end

    private

    attr_reader :bot, :logger

    def handle_message(message)
      text = message.text.to_s
      action_class = MESSAGE_ACTIONS[text.split.first]
      return action_class.call(bot: bot, update: message) if action_class

      resume_pending(message, text)
    end

    def resume_pending(message, text)
      return if text.blank? || text.start_with?("/")

      pending = PendingAction.take(message.from&.id)
      return if pending.blank?

      action_class = MESSAGE_ACTIONS[pending[:command]]
      return unless action_class

      action_class.call(bot: bot, update: message, pending: pending)
    end
  end
end
