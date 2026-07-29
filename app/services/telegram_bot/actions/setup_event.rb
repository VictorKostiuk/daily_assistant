module TelegramBot
  module Actions
    class SetupEvent < Base
      COMMAND = "/setup_event".freeze

      def call
        return send_message(t("commands.setup_event.not_linked")) if current_user.blank?
        return send_message(t("commands.setup_event.google_missing")) unless google_connected?
        return ask_for_description if description.blank?

        event = Integrations::OpenRouter::ParseEvent.call(text: description, time_zone: time_zone)
        created = Integrations::Google::CreateEvent.call(user: current_user, event: event)
        telegram_account.touch(:last_interaction_at)

        send_message(confirmation_for(event, created), disable_web_page_preview: true)
      rescue Integrations::OpenRouter::Client::NotConfigured => error
        Rails.logger.error("[telegram_bot] setup_event unavailable: #{error.message}")
        send_message(t("commands.setup_event.unavailable"))
      rescue Integrations::OpenRouter::Client::RequestFailed, Integrations::OpenRouter::ParseEvent::UnparseableResponse => error
        Rails.logger.warn("[telegram_bot] setup_event parsing failed: #{error.class}: #{error.message}")
        send_message(t("commands.setup_event.not_understood"))
      rescue Integrations::Google::Client::ScopeMissing
        send_message(t("commands.setup_event.calendar_missing"))
      rescue ::Google::Apis::Error, ::Signet::AuthorizationError => error
        Rails.logger.warn("[telegram_bot] setup_event failed: #{error.class}: #{error.message}")
        send_message(t("commands.setup_event.failed"))
      end

      private

      def ask_for_description
        PendingAction.set(update.from&.id, COMMAND)
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
