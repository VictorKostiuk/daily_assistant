module TelegramBot
  module Actions
    class TodaysEvents < Base
      BUTTON_TEXT_LIMIT = 48
      ACTION_TYPE = "todays_events".freeze

      def call
        return send_message(t("commands.todays_events.not_linked")) if current_user.blank?
        return send_message(t("commands.todays_events.google_missing")) unless google_connected?

        perform_lookup
      end

      private

      def perform_lookup
        started_at = Time.current

        entries = Integrations::Google::TodaysEvents.call(user: current_user)
        telegram_account.touch(:last_interaction_at)

        record_action!(
          action_type: ACTION_TYPE,
          status: :succeeded,
          display_text: "#{entries.size} event(s)",
          started_at: started_at
        )
        send_schedule(entries)
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: "commands.todays_events", action_type: ACTION_TYPE, started_at: started_at)
      end

      def google_connected?
        current_user.google_integration&.connected?
      end

      def send_schedule(entries)
        return send_message(t("commands.todays_events.empty", name: sender_name)) if entries.empty?

        markup = schedule_markup(entries)
        options = markup ? { reply_markup: markup } : {}

        send_message(t("commands.todays_events.heading"), **options)
      end

      def schedule_markup(entries)
        linkable = entries.select { |entry| entry.html_link.present? }
        return if linkable.empty?

        rows = linkable.each_with_index.map { |entry, index| button_for(entry, index) }
        Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: rows.map { |button| [ button ] })
      end

      def button_for(entry, index)
        Telegram::Bot::Types::InlineKeyboardButton.new(text: button_label(entry, index), url: entry.html_link)
      end

      def button_label(entry, index)
        label = "#{index + 1}. #{time_label(entry)} — #{title_for(entry)}"
        label = "#{label} (#{entry.location})" if entry.location.present?

        label.truncate(BUTTON_TEXT_LIMIT)
      end

      def title_for(entry)
        entry.title.presence || t("commands.todays_events.untitled")
      end

      def time_label(entry)
        return t("commands.todays_events.all_day") if entry.all_day

        I18n.l(entry.starts_at, format: :hour_minute)
      end
    end
  end
end
