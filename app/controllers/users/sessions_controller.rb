module Users
  class SessionsController < Devise::SessionsController
    rate_limit to: 10, within: 3.minutes, only: :create

    def create
      self.resource = warden.authenticate(auth_options)
      if resource&.active? && resource.admin?
        set_flash_message!(:notice, :signed_in)
        sign_in(resource_name, resource)
        respond_with resource, location: after_sign_in_path_for(resource)
      else
        warden.logout(resource_name) if warden.authenticated?(resource_name)
        flash.now[:alert] = t("devise.failure.invalid", authentication_keys: User.human_attribute_name(:email))
        self.resource = resource_class.new(sign_in_params)
        clean_up_passwords(resource)
        render :new, status: :unprocessable_content
      end
    end
  end
end
