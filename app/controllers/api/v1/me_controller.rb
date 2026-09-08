module Api
  module V1
    class MeController < BaseController
      def show
        render json: {
          id: current_api_user.id,
          email: current_api_user.email,
          first_name: current_api_user.first_name,
          last_name: current_api_user.last_name,
          time_zone: current_api_user.time_zone,
          locale: current_api_user.locale,
          role: current_api_user.role,
          status: current_api_user.status
        }
      end
    end
  end
end
