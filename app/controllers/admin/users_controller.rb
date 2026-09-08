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

    def update
      @user = User.find(params[:id])

      if @user == current_user
        return redirect_to admin_user_path(@user), alert: t("admin.users.show.cannot_edit_self")
      end

      @user.assign_attributes(user_params)
      changes = @user.changes.slice("role", "status")

      if changes.present?
        record_change!(changes)
        redirect_to admin_user_path(@user), notice: t("admin.users.show.updated")
      else
        redirect_to admin_user_path(@user)
      end
    rescue ArgumentError
      redirect_to admin_user_path(@user), alert: t("admin.users.show.invalid_value")
    end

    private

    def record_change!(changes)
      ActiveRecord::Base.transaction do
        @user.save!
        AuditLog.create!(
          actor: current_user,
          target_user: @user,
          auditable: @user,
          action: "user.updated",
          changes_data: changes,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end
    end

    def user_params
      params.require(:user).permit(:role, :status)
    end
  end
end
