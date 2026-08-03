module TelegramBot
  module Actions
    class RemindersList < Base
      ACTION_TYPE = "reminders_list".freeze
      I18N_SCOPE = "commands.reminders_list".freeze

      def call
        return send_message(t("#{I18N_SCOPE}.not_linked")) if current_user.blank?

        reminders = current_user.reminders.pending.order(:scheduled_at).limit(25)
        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: "#{reminders.size} reminder(s)")

        return send_message(t("#{I18N_SCOPE}.empty")) if reminders.empty?

        send_message(list_text(reminders))
      end

      private

      def list_text(reminders)
        lines = reminders.each_with_index.map { |reminder, index| line_for(reminder, index) }
        [ t("#{I18N_SCOPE}.heading"), "", *lines ].join("\n")
      end

      def line_for(reminder, index)
        "#{index + 1}. #{I18n.l(reminder.scheduled_at, format: :long)} — #{reminder.title}"
      end
    end
  end
end
