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
      # Terminal confirmation, for members and staff alike. Redirecting here
      # sent members to the staff-only HTML sign-in, which rejected the password
      # they had just set. No session, no new token, no redirect.
      render :completed, status: :ok
    else
      render :edit, status: :unprocessable_content
    end
  end
end
