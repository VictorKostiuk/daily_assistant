require "openai"

module Integrations
  module OpenRouter
    class Client
      class NotConfigured < StandardError; end
      class RequestFailed < StandardError; end

      REQUEST_TIMEOUT = 30

      def chat(system:, user:, model: nil)
        raise NotConfigured, "OPEN_ROUTER_KEY is missing" if settings.api_key.blank?

        response = client.chat(parameters: {
          model: model.presence || settings.model,
          temperature: 0,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: system },
            { role: "user", content: user }
          ]
        })

        content = response.dig("choices", 0, "message", "content")
        raise RequestFailed, "OpenRouter returned no content: #{response.dig('error', 'message')}" if content.blank?

        content
      rescue Faraday::Error => error
        raise RequestFailed, "#{error.class}: #{error.message}"
      end

      private

      def client
        @client ||= ::OpenAI::Client.new(
          access_token: settings.api_key,
          uri_base: BASE_URI,
          request_timeout: REQUEST_TIMEOUT,
          extra_headers: {
            "HTTP-Referer" => settings.app_url,
            "X-Title" => settings.app_name
          }
        )
      end

      def settings
        Integrations::OpenRouter.settings
      end
    end
  end
end
