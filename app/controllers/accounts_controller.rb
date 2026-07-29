class AccountsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    @telegram_account = @user.telegram_account
    @google_integration = @user.google_integration
    @connected_integrations_count = @user.user_integrations.connected.count
    @connected_integrations_count += 1 if @telegram_account
  end
end
