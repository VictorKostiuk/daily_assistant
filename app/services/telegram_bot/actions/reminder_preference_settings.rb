module TelegramBot
  module Actions
    class ReminderPreferenceSettings < Base
      COMMAND = "/reminder_preference".freeze
      ACTION_TYPE = "reminder_preference_settings".freeze
      I18N_SCOPE = "commands.reminder_preference".freeze

      def call
        return send_message(t("#{I18N_SCOPE}.not_linked")) if current_user.blank?

        if argument == "ask"
          set_mode(:ask_every_time)
        elsif argument == "off"
          set_mode(:disabled_by_default)
        elsif argument.start_with?("always")
          set_always_apply_default
        elsif argument.blank?
          show_status
        else
          send_message(t("#{I18N_SCOPE}.usage"))
        end
      end

      private

      def argument
        @argument ||= update.text.to_s.sub(/\A#{COMMAND}(@\S+)?/, "").strip.downcase
      end

      def preference
        current_user.reminder_preference || current_user.build_reminder_preference
      end

      def set_mode(mode)
        preference.update!(event_reminder_mode: mode)

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: mode.to_s)
        send_message(t("#{I18N_SCOPE}.set_#{mode}"))
      end

      def set_always_apply_default
        remainder = argument.sub(/\Aalways\b/, "").strip
        return send_message(t("#{I18N_SCOPE}.usage")) unless remainder.match?(/\A\d+\z/)

        minutes = remainder.to_i.clamp(0, Reminder::MAX_OFFSET_MINUTES)
        preference.update!(event_reminder_mode: :always_apply_default, default_event_offset_minutes: minutes)

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: "always_apply_default #{minutes}")
        send_message(t("#{I18N_SCOPE}.set_always_apply_default_with_offset", minutes: minutes))
      end

      def show_status
        current_preference = current_user.reminder_preference

        if current_preference.blank? || current_preference.ask_every_time?
          send_message(t("#{I18N_SCOPE}.status_ask"))
        elsif current_preference.always_apply_default?
          send_message(t("#{I18N_SCOPE}.status_always", minutes: current_preference.default_event_offset_minutes))
        else
          send_message(t("#{I18N_SCOPE}.status_off"))
        end
      end
    end
  end
end
