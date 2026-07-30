module TelegramBot
  module Actions
    class SetupEvent < Base
      COMMAND = "/setup_event".freeze
      ACTION_TYPE = "setup_event".freeze

      def call
        return send_message(t("commands.setup_event.not_linked")) if current_user.blank?
        return send_message(t("commands.setup_event.google_missing")) unless google_connected?
        return ask_for_description if description.blank?

        perform_setup
      end

      private

      def perform_setup
        started_at = Time.current

        event = Integrations::OpenRouter::ParseEvent.call(text: description, time_zone: time_zone)
        created = Integrations::Google::CreateEvent.call(user: current_user, event: event)
        telegram_account.touch(:last_interaction_at)

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: event.title, started_at: started_at)
        send_message(confirmation_for(event, created), disable_web_page_preview: true)
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: "commands.setup_event", action_type: ACTION_TYPE, display_text: description, started_at: started_at)
      end

      def ask_for_description
        PendingAction.set(update.from&.id, command: COMMAND, stage: "description")
        send_message(t("commands.setup_event.prompt"))
      end

      def description
        @description ||= update.text.to_s.sub(/\A#{COMMAND}(@\S+)?/, "").strip
      end

      def google_connected?
        current_user.google_integration&.connected?
      end

      def time_zone
        @time_zone ||= current_user.time_zone.presence || Time.zone.name
      end

      def confirmation_for(event, created)
        lines = [
          t("commands.setup_event.created", title: event.title),
          t("commands.setup_event.when", time: time_label(event))
        ]
        lines << t("commands.setup_event.where", location: event.location) if event.location.present?
        lines << created.html_link if created.html_link.present?

        lines.join("\n")
      end

      def time_label(event)
        return I18n.l(event.starts_at.to_date, format: :long) if event.all_day

        "#{I18n.l(event.starts_at, format: :long)} – #{I18n.l(event.ends_at, format: :hour_minute)}"
      end
    end
  end
end
