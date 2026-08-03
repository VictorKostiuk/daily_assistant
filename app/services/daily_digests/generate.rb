module DailyDigests
  class Generate
    Result = Struct.new(:text, :empty, keyword_init: true)

    def self.call(digest)
      new(digest).call
    end

    def initialize(digest)
      @digest = digest
    end

    def call
      Time.use_zone(time_zone) do
        events = digest.include_calendar_events? ? event_entries.to_a : []
        pending_reminders = digest.include_reminders? ? reminder_entries.to_a : []

        Result.new(text: render(events, pending_reminders), empty: events.empty? && pending_reminders.empty?)
      end
    end

    private

    attr_reader :digest

    def user
      digest.user
    end

    def time_zone
      digest.time_zone.presence || user.time_zone.presence || Time.zone.name
    end

    def event_entries
      scope = user.calendar_events.confirmed.where(starts_at: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day)
      scope = scope.where(all_day: false) unless digest.include_all_day_events?
      scope.order(:starts_at)
    end

    def reminder_entries
      user.reminders.pending.where(scheduled_at: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day).order(:scheduled_at)
    end

    def render(events, pending_reminders)
      lines = [ I18n.t("telegram_bot.daily_digest.greeting", name: user.first_name.presence || I18n.t("telegram_bot.fallback_name")) ]

      if events.empty? && pending_reminders.empty?
        lines << ""
        lines << I18n.t("telegram_bot.daily_digest.empty")
        return lines.join("\n")
      end

      if events.any?
        lines << ""
        lines << I18n.t("telegram_bot.daily_digest.schedule_heading")
        events.each { |event| lines << event_line(event) }
      end

      if pending_reminders.any?
        lines << ""
        lines << I18n.t("telegram_bot.daily_digest.reminders_heading")
        pending_reminders.each { |reminder| lines << "• #{reminder.title}" }
      end

      lines.join("\n")
    end

    def event_line(event)
      time_label = event.all_day ? I18n.t("telegram_bot.daily_digest.all_day") : I18n.l(event.starts_at, format: :hour_minute)
      "#{time_label} — #{event.title.presence || I18n.t('telegram_bot.daily_digest.untitled')}"
    end
  end
end
