class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  protected

  def configure_permitted_parameters
    user_attributes = [:first_name, :last_name, :time_zone, :locale]

    devise_parameter_sanitizer.permit(:sign_up, keys: user_attributes)
    devise_parameter_sanitizer.permit(:account_update, keys: user_attributes)
  end

  def after_update_path_for(_resource)
    account_path
  end

  private

  def user_not_authorized
    redirect_to root_path, alert: t("errors.not_authorized")
  end
end
