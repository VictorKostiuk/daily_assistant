module Admin
  class UsersController < BaseController
    def index
      @pagination = paginate(User.order(created_at: :desc))
      @action_counts = ActionExecution.where(user_id: @pagination.records.map(&:id)).group(:user_id).count
    end

    def show
      @user = User.find(params[:id])
      @pagination = paginate(@user.action_executions.order(created_at: :desc))
    end
  end
end
