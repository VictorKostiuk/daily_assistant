module Api
  module V1
    class AiMessagesController < BaseController
      SYSTEM_INSTRUCTION = "You are the assistant for Daily Assistant. Answer the user's message directly and concisely in plain text. You have no memory of previous messages and you cannot take actions on the user's behalf.".freeze
      ALLOWED_FIELDS = ([ "message" ] + SourceMetadata::FIELDS).freeze
      MESSAGE_MAX = 10_000

      def create
        raw = raw_body
        return if raw.nil?

        message = require_message(raw)
        return if message.nil?

        source = SourceMetadata.load(SourceMetadata.dump(raw.slice(*SourceMetadata::FIELDS)))

        execution = nil
        begin
          execution = current_api_user.action_executions.create!(
            action_type: "ai.message",
            source: :api,
            status: :processing,
            started_at: Time.current,
            display_text: message.gsub(/\s+/, " ")[0, 120]
          )

          answer = Integrations::OpenRouter::Client.new.chat(
            system: SYSTEM_INSTRUCTION,
            user: message,
            response_format: nil,
            temperature: 0.7
          )

          complete_row!(execution, status: :succeeded)
          render json: {
            id: execution.id,
            message: answer,
            model: Rails.application.config.x.open_router.model
          }.merge(source.symbolize_keys)
        rescue Integrations::OpenRouter::Client::NotConfigured
          mark_failed(execution, "integration_unavailable")
          render_integration_unavailable
        rescue Integrations::OpenRouter::Client::RequestFailed
          mark_failed(execution, "provider_error")
          render_provider_error
        rescue StandardError
          mark_failed(execution, "internal_error")
          render_internal_error
        end
      end

      private

      def raw_body
        raw = request.request_parameters.stringify_keys
        unknown = raw.keys - ALLOWED_FIELDS
        if unknown.any?
          render_validation_error(unknown.index_with { [ "is unknown" ] })
          return
        end

        raw
      end

      def require_message(raw)
        message = raw["message"]
        if !message.is_a?(String) || message.strip.empty?
          render_validation_error("message" => [ "can't be blank" ])
          return
        end
        if message.length > MESSAGE_MAX
          render_validation_error("message" => [ "is too long" ])
          return
        end

        message
      end

      def complete_row!(execution, status:, error_message: nil)
        completed_at = Time.current
        execution.update!(
          status: status,
          error_message: error_message,
          completed_at: completed_at,
          duration_ms: ((completed_at - execution.started_at) * 1000).round
        )
      end

      def mark_failed(execution, code)
        return if execution.nil?

        complete_row!(execution, status: :failed, error_message: code)
      rescue StandardError
        nil
      end
    end
  end
end
