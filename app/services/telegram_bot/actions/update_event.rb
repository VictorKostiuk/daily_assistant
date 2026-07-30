module TelegramBot
  module Actions
    class UpdateEvent < Base
      COMMAND = "/update_event".freeze
      ACTION_TYPE = "update_event".freeze
      I18N_SCOPE = "commands.update_event".freeze
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

        result = Integrations::OpenRouter::ParseEventUpdate.call(text: description, time_zone: time_zone, candidates: candidates)
        matched = candidates.find { |candidate| candidate.id == result.event_id } if result.event_id.present?

        if matched.nil?
          record_action!(action_type: ACTION_TYPE, status: :failed, display_text: description, error_message: "no matching event", started_at: started_at)
          return send_message(t("#{I18N_SCOPE}.not_found"))
        end

        PendingAction.set(
          update.from&.id,
          command: COMMAND,
          stage: "confirmation",
          event_id: result.event_id,
          event: event_to_hash(result.event)
        )
        send_message(confirmation_message(result.event))
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: I18N_SCOPE, action_type: ACTION_TYPE, display_text: description, started_at: started_at)
      end

      def resume_confirmation
        unless affirmative?(update.text)
          send_message(t("#{I18N_SCOPE}.discarded"))
          return
        end

        started_at = Time.current
        event = event_from_hash(pending[:event])

        updated = Integrations::Google::UpdateEvent.call(user: current_user, event_id: pending[:event_id], event: event)
        telegram_account.touch(:last_interaction_at)

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: event.title, started_at: started_at)
        send_message(confirmed_message(event, updated))
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: I18N_SCOPE, action_type: ACTION_TYPE, display_text: event&.title, started_at: started_at)
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

      def event_to_hash(event)
        {
          title: event.title,
          description: event.description,
          location: event.location,
          starts_at: event.starts_at,
          ends_at: event.ends_at,
          all_day: event.all_day
        }
      end

      def event_from_hash(hash)
        Integrations::OpenRouter::EventParsing::Event.new(**hash)
      end

      def confirmation_message(event)
        lines = [ t("#{I18N_SCOPE}.confirm", title: event.title, time: time_label(event)) ]
        lines << t("#{I18N_SCOPE}.confirm_where", location: event.location) if event.location.present?
        lines << t("#{I18N_SCOPE}.confirm_hint")

        lines.join("\n")
      end

      def confirmed_message(event, updated)
        lines = [
          t("#{I18N_SCOPE}.updated", title: event.title),
          t("#{I18N_SCOPE}.when", time: time_label(event))
        ]
        lines << t("#{I18N_SCOPE}.where", location: event.location) if event.location.present?
        lines << updated.html_link if updated.html_link.present?

        lines.join("\n")
      end

      def time_label(event)
        return I18n.l(event.starts_at.to_date, format: :long) if event.all_day

        "#{I18n.l(event.starts_at, format: :long)} – #{I18n.l(event.ends_at, format: :hour_minute)}"
      end
    end
  end
end
