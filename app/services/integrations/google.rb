module Integrations
  module Google
    def self.settings
      Rails.application.config.x.google_oauth
    end

    def self.granted_services(scopes)
      granted = Array(scopes)

      settings.service_scopes.select { |_service, required| (required - granted).empty? }.keys
    end
  end
end
