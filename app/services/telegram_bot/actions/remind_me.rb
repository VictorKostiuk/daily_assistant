module TelegramBot
  module Actions
    class RemindMe < Base
      COMMAND = "/remind".freeze
      ACTION_TYPE = "remind_me".freeze
      I18N_SCOPE = "commands.remind_me".freeze

      def call
        return send_message(t("#{I18N_SCOPE}.not_linked")) if current_user.blank?
        return ask_for_description if description.blank?

        perform_remind
      end

      private

      def perform_remind
        started_at = Time.current

        result = Integrations::OpenRouter::ParseReminder.call(text: description, time_zone: time_zone, candidates: candidates)

        case result.kind
        when "event"
          create_event_reminder(result, started_at)
        when "standalone"
          create_standalone_reminder(result, started_at)
        end
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: I18N_SCOPE, action_type: ACTION_TYPE, display_text: description, started_at: started_at)
      end

      def create_event_reminder(result, started_at)
        matched = candidates.find { |candidate| candidate.id.to_s == result.event_id } if result.event_id.present?

        if matched.nil?
          record_action!(action_type: ACTION_TYPE, status: :failed, display_text: description, error_message: "no matching event", started_at: started_at)
          return send_message(t("#{I18N_SCOPE}.event_not_found"))
        end

        reminder = Reminders::Create.call(
          user: current_user,
          title: result.title.presence || matched.title,
          scheduled_at: matched.starts_at - result.offset_minutes.to_i.minutes,
          remindable: matched,
          offset_minutes: result.offset_minutes,
          source: :telegram
        )

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: reminder.title, started_at: started_at)
        send_message(t("#{I18N_SCOPE}.scheduled", title: reminder.title, time: I18n.l(reminder.scheduled_at, format: :long)))
      end

      def create_standalone_reminder(result, started_at)
        reminder = Reminders::Create.call(
          user: current_user,
          title: result.title,
          scheduled_at: result.scheduled_at,
          source: :telegram
        )

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: reminder.title, started_at: started_at)
        send_message(t("#{I18N_SCOPE}.scheduled", title: reminder.title, time: I18n.l(reminder.scheduled_at, format: :long)))
      end

      def ask_for_description
        PendingAction.set(update.from&.id, command: COMMAND, stage: "description")
        send_message(t("#{I18N_SCOPE}.prompt"))
      end

      def description
        @description ||= update.text.to_s.sub(/\A#{COMMAND}(@\S+)?/, "").strip
      end

      def candidates
        @candidates ||= current_user.calendar_events.confirmed.where(starts_at: Time.current..).order(:starts_at).limit(50)
      end

      def time_zone
        @time_zone ||= current_user.time_zone.presence || Time.zone.name
      end
    end
  end
end
