module TelegramBot
  module Actions
    class CancelReminder < Base
      COMMAND = "/cancel_reminder".freeze
      ACTION_TYPE = "cancel_reminder".freeze
      I18N_SCOPE = "commands.cancel_reminder".freeze
      AFFIRMATIVE = %w[yes y yeah yep sure confirm].freeze

      def call
        return send_message(t("#{I18N_SCOPE}.not_linked")) if current_user.blank?
        return resume_confirmation if awaiting_confirmation?
        return ask_for_description if description.blank?

        match_and_propose
      end

      private

      def awaiting_confirmation?
        pending.present? && pending[:stage] == "confirmation"
      end

      def ask_for_description
        PendingAction.set(update.from&.id, command: COMMAND, stage: "description")
        send_message(t("#{I18N_SCOPE}.prompt"))
      end

      def match_and_propose
        started_at = Time.current

        candidates = current_user.reminders.pending.order(:scheduled_at).limit(25)
        return send_message(t("#{I18N_SCOPE}.no_reminders")) if candidates.empty?

        reminder_id = Integrations::OpenRouter::MatchReminder.call(text: description, time_zone: time_zone, candidates: candidates)
        matched = candidates.find { |candidate| candidate.id.to_s == reminder_id } if reminder_id.present?

        if matched.nil?
          record_action!(action_type: ACTION_TYPE, status: :failed, display_text: description, error_message: "no matching reminder", started_at: started_at)
          return send_message(t("#{I18N_SCOPE}.not_found"))
        end

        PendingAction.set(update.from&.id, command: COMMAND, stage: "confirmation", reminder_id: matched.id, title: matched.title)
        send_message(confirmation_message(matched))
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: I18N_SCOPE, action_type: ACTION_TYPE, display_text: description, started_at: started_at)
      end

      def resume_confirmation
        unless affirmative?(update.text)
          send_message(t("#{I18N_SCOPE}.discarded"))
          return
        end

        started_at = Time.current
        reminder = current_user.reminders.find_by(id: pending[:reminder_id])

        if reminder.blank? || !reminder.pending?
          return send_message(t("#{I18N_SCOPE}.already_gone"))
        end

        reminder.update!(status: :cancelled, cancelled_at: Time.current)
        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: reminder.title, started_at: started_at)
        send_message(t("#{I18N_SCOPE}.cancelled", title: reminder.title))
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: I18N_SCOPE, action_type: ACTION_TYPE, display_text: pending[:title], started_at: started_at)
      end

      def affirmative?(text)
        AFFIRMATIVE.include?(text.to_s.strip.downcase)
      end

      def description
        @description ||= update.text.to_s.sub(/\A#{COMMAND}(@\S+)?/, "").strip
      end

      def time_zone
        @time_zone ||= current_user.time_zone.presence || Time.zone.name
      end

      def confirmation_message(matched)
        "#{t("#{I18N_SCOPE}.confirm", title: matched.title, time: I18n.l(matched.scheduled_at, format: :long))}\n#{t("#{I18N_SCOPE}.confirm_hint")}"
      end
    end
  end
end
