module TelegramBot
  module Actions
    class DailyDigestSettings < Base
      COMMAND = "/daily_digest".freeze
      ACTION_TYPE = "daily_digest_settings".freeze
      I18N_SCOPE = "commands.daily_digest".freeze

      def call
        return send_message(t("#{I18N_SCOPE}.not_linked")) if current_user.blank?

        if argument == "off"
          disable!
        elsif argument.start_with?("on")
          enable!
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

      def disable!
        digest = current_user.daily_digest
        digest&.update!(enabled: false, next_delivery_at: nil)

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: "disabled")
        send_message(t("#{I18N_SCOPE}.disabled"))
      end

      def enable!
        time_string = argument.sub(/\Aon\b/, "").strip
        delivery_time = parse_time(time_string)

        return send_message(t("#{I18N_SCOPE}.usage")) if delivery_time.blank?

        digest = current_user.daily_digest || current_user.build_daily_digest
        digest.assign_attributes(
          enabled: true,
          delivery_time: delivery_time,
          time_zone: current_user.time_zone.presence || Time.zone.name
        )
        digest.next_delivery_at = DailyDigests::CalculateNextDelivery.call(digest)
        digest.save!

        record_action!(action_type: ACTION_TYPE, status: :succeeded, display_text: "enabled at #{time_string}")
        send_message(t("#{I18N_SCOPE}.enabled", time: time_string))
      end

      def show_status
        digest = current_user.daily_digest

        if digest&.enabled?
          send_message(t("#{I18N_SCOPE}.status_on", time: digest.local_delivery_time.strftime("%H:%M")))
        else
          send_message(t("#{I18N_SCOPE}.status_off"))
        end
      end

      def parse_time(value)
        return nil if value.blank?

        Time.use_zone(current_user.time_zone.presence || Time.zone.name) { Time.zone.parse(value) }
      rescue ArgumentError
        nil
      end
    end
  end
end
