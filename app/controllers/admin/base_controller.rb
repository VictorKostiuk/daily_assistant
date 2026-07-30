module Admin
  class BaseController < ApplicationController
    include Paginatable

    before_action :authenticate_user!
    before_action :require_admin!

    private

    def require_admin!
      return if current_user.admin?

      redirect_to root_path, alert: t("admin.not_authorized")
    end
  end
end
