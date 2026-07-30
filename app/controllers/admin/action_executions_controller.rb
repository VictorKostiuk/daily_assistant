module Admin
  class ActionExecutionsController < BaseController
    def index
      scope = ActionExecution.order(created_at: :desc).includes(:user)

      if params[:user_id].present?
        @filtered_user = User.find_by(id: params[:user_id])
        scope = scope.where(user_id: @filtered_user.id) if @filtered_user
      end

      @pagination = paginate(scope)
    end
  end
end
