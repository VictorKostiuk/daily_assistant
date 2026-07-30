class ActionExecutionsController < ApplicationController
  include Paginatable

  before_action :authenticate_user!

  def index
    @pagination = paginate(current_user.action_executions.order(created_at: :desc))
  end
end
