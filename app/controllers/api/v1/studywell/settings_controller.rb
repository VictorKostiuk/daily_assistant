module Api
  module V1
    module Studywell
      class SettingsController < Api::V1::BaseController
        def show
          render json: settings_json
        end

        def update
          attrs = InputValidator.settings_patch(request.request_parameters)
          if current_api_user.update(time_zone: attrs["time_zone"])
            render json: settings_json
          else
            render_validation_error(current_api_user.errors.messages)
          end
        end

        private

        def settings_json
          {
            time_zone: current_api_user.time_zone,
            needs_time_zone_setup: InputValidator.time_zone_needs_setup?(current_api_user.time_zone)
          }
        end
      end
    end
  end
end
