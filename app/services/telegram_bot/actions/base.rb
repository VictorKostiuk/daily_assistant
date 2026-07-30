module TelegramBot
  module Actions
    class Base
      def self.call(bot:, update:, pending: nil)
        new(bot: bot, update: update, pending: pending).call
      end

      def self.call_callback(bot:, update:)
        new(bot: bot, update: update).call_callback
      end

      def initialize(bot:, update:, pending: nil)
        @bot = bot
        @update = update
        @pending = pending
      end

      def call
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      def call_callback
        call
      end

      private

      attr_reader :bot, :update, :pending

      def send_message(text, **options)
        bot.api.send_message({ chat_id: chat_id, text: text }.merge(options))
      end

      def answer_callback(text: nil)
        return unless update.is_a?(Telegram::Bot::Types::CallbackQuery)

        payload = { callback_query_id: update.id }
        payload[:text] = text if text.present?

        bot.api.answer_callback_query(payload)
      end

      def chat_id
        return update.chat.id if update.respond_to?(:chat) && update.chat
        return update.message.chat.id if update.respond_to?(:message) && update.message&.chat
        return update.from.id if update.respond_to?(:from) && update.from

        nil
      end

      def sender_name
        update.from&.first_name.presence || t("fallback_name")
      end

      def telegram_account
        return @telegram_account if defined?(@telegram_account)

        @telegram_account = TelegramAccount.find_by(telegram_user_id: update.from&.id)
      end

      def current_user
        telegram_account&.user
      end

      def record_action!(action_type:, status:, display_text: nil, error_message: nil, started_at: nil)
        return if current_user.blank?

        completed_at = Time.current

        current_user.action_executions.create!(
          action_type: action_type,
          source: :telegram,
          status: status,
          display_text: display_text,
          error_message: error_message,
          started_at: started_at,
          completed_at: completed_at,
          duration_ms: started_at ? ((completed_at - started_at) * 1000).round : nil
        )
      rescue StandardError => error
        Rails.logger.error("[telegram_bot] failed to record action execution: #{error.class}: #{error.message}")
      end

      def handle_event_error!(error, i18n_scope:, action_type:, display_text: nil, started_at: nil)
        record_action!(action_type: action_type, status: :failed, display_text: display_text, error_message: error.message, started_at: started_at)

        case error
        when Integrations::OpenRouter::Client::NotConfigured
          Rails.logger.error("[telegram_bot] #{action_type} unavailable: #{error.message}")
          send_message(t("#{i18n_scope}.unavailable"))
        when Integrations::OpenRouter::Client::RequestFailed, Integrations::OpenRouter::EventParsing::UnparseableResponse
          Rails.logger.warn("[telegram_bot] #{action_type} parsing failed: #{error.class}: #{error.message}")
          send_message(t("#{i18n_scope}.not_understood"))
        when Integrations::Google::Client::ScopeMissing
          send_message(t("#{i18n_scope}.calendar_missing"))
        when ::Google::Apis::Error, ::Signet::AuthorizationError
          Rails.logger.warn("[telegram_bot] #{action_type} failed: #{error.class}: #{error.message}")
          send_message(t("#{i18n_scope}.failed"))
        else
          raise error
        end
      end

      def t(key, **options)
        I18n.t("telegram_bot.#{key}", **options)
      end
    end
  end
end
