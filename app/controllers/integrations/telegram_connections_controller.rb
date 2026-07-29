module Integrations
  class TelegramConnectionsController < ApplicationController
    before_action :authenticate_user!

    def create
      link = Integrations::Telegram::ConnectionLink.call(user: current_user)

      if link.blank?
        return redirect_to account_path, alert: t("integrations.telegram_connections.unavailable"), status: :see_other
      end

      redirect_to link, allow_other_host: true, status: :see_other
    end

    def destroy
      current_user.telegram_account&.destroy!

      redirect_to account_path, notice: t("integrations.telegram_connections.disconnected"), status: :see_other
    end
  end
end
