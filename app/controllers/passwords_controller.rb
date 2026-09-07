class PasswordsController < ApplicationController
  # Account-recovery transport: Core-hosted HTML form for the emailed reset
  # token. Not an admin page and not a Devise member account route.

  def edit
    @reset_password_token = params[:reset_password_token]
  end

  def update
    @user = User.reset_password_by_token(
      reset_password_token: params[:reset_password_token],
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    )
    @reset_password_token = params[:reset_password_token]

    if @user.errors.empty?
      redirect_to new_user_session_path, notice: t("devise.passwords.updated_not_active")
    else
      render :edit, status: :unprocessable_content
    end
  end
end
