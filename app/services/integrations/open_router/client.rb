require "openai"

module Integrations
  module OpenRouter
    class Client
      class NotConfigured < StandardError; end
      class RequestFailed < StandardError; end

      REQUEST_TIMEOUT = 30

      def chat(system:, user:, model: nil, response_format: { type: "json_object" }, temperature: 0)
        raise NotConfigured, "OPEN_ROUTER_KEY is missing" if settings.api_key.blank?

        parameters = {
          model: model.presence || settings.model,
          temperature: temperature,
          messages: [
            { role: "system", content: system },
            { role: "user", content: user }
          ]
        }
        parameters[:response_format] = response_format unless response_format.nil?

        extract_text!(client.chat(parameters: parameters))
      rescue Faraday::Error => error
        raise RequestFailed, "#{error.class}: #{error.message}"
      end

      private

      def extract_text!(response)
        unless response.is_a?(Hash)
          raise RequestFailed, "OpenRouter returned a malformed response"
        end

        choices = response["choices"]
        first = choices.is_a?(Array) ? choices.first : nil
        message = first.is_a?(Hash) ? first["message"] : nil
        content = message.is_a?(Hash) ? message["content"] : nil

        unless content.is_a?(String) && content.present?
          raise RequestFailed, "OpenRouter returned no content"
        end

        content
      end

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
