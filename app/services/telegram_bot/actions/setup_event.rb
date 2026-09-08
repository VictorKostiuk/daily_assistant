module TelegramBot
  module Actions
    class SetupEvent < Base
      COMMAND = "/setup_event".freeze
      ACTION_TYPE = "setup_event".freeze
      NEGATIVE_WORDS = %w[no none skip never].freeze
      OFFSET_PATTERN = /(\d+)\s*(minute|min|hour|hr|day)/

      def call
        return send_message(t("commands.setup_event.not_linked")) if current_user.blank?
        return send_message(t("commands.setup_event.google_missing")) unless google_connected?
        return handle_reminder_choice if awaiting_reminder_choice?
        return ask_for_description if description.blank?

        perform_setup
      end

      private

      def perform_setup
        started_at = Time.current

        event = Integrations::OpenRouter::ParseEvent.call(text: description, time_zone: time_zone)
        result = Integrations::Google::CreateEvent.call(user: current_user, event: event)
        telegram_account.touch(:last_interaction_at)

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: event.title, started_at: started_at)
        send_message(confirmation_for(event, result.provider_event), disable_web_page_preview: true)

        offer_reminder(result)
      rescue StandardError => error
        handle_event_error!(error, i18n_scope: "commands.setup_event", action_type: ACTION_TYPE, display_text: description, started_at: started_at)
      end

      def offer_reminder(result)
        # Resolve against the calendar CreateEvent selected, not a separately
        # derived one. A provider event id is unique per calendar, not per user:
        # the same id in a second calendar would otherwise attach the reminder
        # to the wrong local event, and so to the wrong time.
        local_event = current_user.calendar_events.find_by(
          provider: "google",
          external_calendar_id: result.calendar_id,
          external_event_id: result.provider_event.id
        )
        return if local_event.blank?

        preference = current_user.reminder_preference

        if preference&.always_apply_default?
          apply_default_reminder(local_event, preference)
        elsif preference.nil? || preference.ask_every_time?
          ask_about_reminder(local_event)
        end
      end

      def apply_default_reminder(local_event, preference)
        minutes = preference.default_event_offset_minutes
        return if minutes.blank?

        Reminders::Create.call(
          user: current_user,
          title: local_event.title,
          scheduled_at: local_event.starts_at - minutes.minutes,
          remindable: local_event,
          offset_minutes: minutes,
          source: :telegram
        )
        send_message(t("commands.setup_event.reminder_added", offset: humanize_offset(minutes)))
      end

      def ask_about_reminder(local_event)
        PendingAction.set(update.from&.id, command: COMMAND, stage: "reminder_choice", calendar_event_id: local_event.id)
        send_message(t("commands.setup_event.ask_reminder"))
      end

      def awaiting_reminder_choice?
        pending.present? && pending[:stage] == "reminder_choice"
      end

      def handle_reminder_choice
        local_event = current_user.calendar_events.find_by(id: pending[:calendar_event_id])
        minutes = local_event.present? ? parse_offset_choice(update.text) : nil

        if minutes.blank?
          send_message(t("commands.setup_event.reminder_skip_ack"))
          return
        end

        Reminders::Create.call(
          user: current_user,
          title: local_event.title,
          scheduled_at: local_event.starts_at - minutes.minutes,
          remindable: local_event,
          offset_minutes: minutes,
          source: :telegram
        )
        send_message(t("commands.setup_event.reminder_added", offset: humanize_offset(minutes)))
      end

      def parse_offset_choice(text)
        normalized = text.to_s.strip.downcase
        return nil if normalized.blank? || NEGATIVE_WORDS.include?(normalized)

        match = normalized.match(OFFSET_PATTERN)
        return nil unless match

        amount = match[1].to_i
        minutes = case match[2]
        when "minute", "min" then amount
        when "hour", "hr" then amount * 60
        when "day" then amount * 1440
        end

        minutes&.clamp(0, Reminder::MAX_OFFSET_MINUTES)
      end

      def humanize_offset(minutes)
        return "#{minutes / 1440} day#{'s' if minutes / 1440 != 1}" if minutes >= 1440 && (minutes % 1440).zero?
        return "#{minutes / 60} hour#{'s' if minutes / 60 != 1}" if minutes >= 60 && (minutes % 60).zero?

        "#{minutes} minute#{'s' if minutes != 1}"
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
