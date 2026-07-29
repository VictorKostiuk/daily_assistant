module Integrations
  class GoogleConnectionsController < ApplicationController
    before_action :authenticate_user!

    def new
      redirect_to account_path, alert: t("integrations.google_connections.unavailable"), status: :see_other
    end

    def create
      auth = request.env["omniauth.auth"]
      return redirect_to(account_path, alert: t("integrations.google_connections.failed")) if auth.blank?

      Integrations::Google::ConnectAccount.call(user: current_user, auth: auth)

      redirect_to account_path, notice: t("integrations.google_connections.connected")
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error("[integrations.google] connect failed: #{error.class} #{error.message}")
      redirect_to account_path, alert: t("integrations.google_connections.failed")
    end

    def destroy
      Integrations::Google::DisconnectAccount.call(user: current_user)

      redirect_to account_path, notice: t("integrations.google_connections.disconnected"), status: :see_other
    end

    def failure
      Rails.logger.warn("[integrations.google] oauth failure: #{params[:message]}")

      redirect_to account_path, alert: t("integrations.google_connections.failed")
    end
  end
end
