module Admin
  class BaseController < ApplicationController
    include Paginatable

    before_action :authenticate_user!
    before_action :authorize_admin_access!

    private

    def authorize_admin_access!
      authorize :admin, :access?, policy_class: AdminPolicy
    end
  end
end
