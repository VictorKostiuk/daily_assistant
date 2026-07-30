module TelegramBot
  module Actions
    class CancelEvent < Base
      COMMAND = "/cancel_event".freeze
      ACTION_TYPE = "cancel_event".freeze
      I18N_SCOPE = "commands.cancel_event".freeze
      AFFIRMATIVE = %w[yes y yeah yep sure confirm].freeze

      def call
        return send_message(t("#{I18N_SCOPE}.not_linked")) if current_user.blank?
        return send_message(t("#{I18N_SCOPE}.google_missing")) unless google_connected?
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

        candidates = Integrations::Google::UpcomingEvents.call(user: current_user)
        return send_message(t("#{I18N_SCOPE}.no_events")) if candidates.empty?

        event_id = Integrations::OpenRouter::ParseEventCancellation.call(text: description, time_zone: time_zone, candidates: candidates)
        matched = candidates.find { |candidate| candidate.id == event_id } if event_id.present?

        if matched.nil?
          record_action!(action_type: ACTION_TYPE, status: :failed, display_text: description, error_message: "no matching event", started_at: started_at)
          return send_message(t("#{I18N_SCOPE}.not_found"))
        end

        PendingAction.set(
          update.from&.id,
          command: COMMAND,
          stage: "confirmation",
          event_id: matched.id,
          title: matched.title,
          starts_at: matched.starts_at,
          all_day: matched.all_day
        )
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

        Integrations::Google::CancelEvent.call(user: current_user, event_id: pending[:event_id])
        telegram_account.touch(:last_interaction_at)

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: pending[:title], started_at: started_at)
        send_message(t("#{I18N_SCOPE}.cancelled", title: pending[:title].presence || t("#{I18N_SCOPE}.untitled")))
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: I18N_SCOPE, action_type: ACTION_TYPE, display_text: pending[:title], started_at: started_at)
      end

      def affirmative?(text)
        AFFIRMATIVE.include?(text.to_s.strip.downcase)
      end

      def google_connected?
        current_user.google_integration&.connected?
      end

      def description
        @description ||= update.text.to_s.sub(/\A#{COMMAND}(@\S+)?/, "").strip
      end

      def time_zone
        @time_zone ||= current_user.time_zone.presence || Time.zone.name
      end

      def confirmation_message(matched)
        title = matched.title.presence || t("#{I18N_SCOPE}.untitled")
        time = matched.all_day ? I18n.l(matched.starts_at.to_date, format: :long) : I18n.l(matched.starts_at, format: :long)

        lines = [ t("#{I18N_SCOPE}.confirm_with_time", title: title, time: time) ]
        lines << t("#{I18N_SCOPE}.confirm_hint")

        lines.join("\n")
      end
    end
  end
end
