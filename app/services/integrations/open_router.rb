module Integrations
  module OpenRouter
    BASE_URI = "https://openrouter.ai/api/v1".freeze

    def self.settings
      Rails.application.config.x.open_router
    end
  end
end
