module TelegramBot
  module Actions
    class TodaysEvents < Base
      def call
        return send_message(t("commands.todays_events.not_linked")) if current_user.blank?
        return send_message(t("commands.todays_events.google_missing")) unless google_connected?

        message = schedule_message
        telegram_account.touch(:last_interaction_at)

        send_message(message)
      rescue Integrations::Google::Client::ScopeMissing
        send_message(t("commands.todays_events.calendar_missing"))
      rescue ::Google::Apis::Error, ::Signet::AuthorizationError => error
        Rails.logger.warn("[telegram_bot] todays_events failed: #{error.class}: #{error.message}")
        send_message(t("commands.todays_events.failed"))
      end

      private

      def google_connected?
        current_user.google_integration&.connected?
      end

      def schedule_message
        entries = Integrations::Google::TodaysEvents.call(user: current_user)
        return t("commands.todays_events.empty", name: sender_name) if entries.empty?

        [ t("commands.todays_events.heading"), "", *entries.map { |entry| line_for(entry) } ].join("\n")
      end

      def line_for(entry)
        "#{time_label(entry)} — #{entry.title.presence || t("commands.todays_events.untitled")}"
      end

      def time_label(entry)
        return t("commands.todays_events.all_day") if entry.all_day

        I18n.l(entry.starts_at, format: :hour_minute)
      end
    end
  end
end
