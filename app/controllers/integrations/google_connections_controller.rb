module Integrations
  class GoogleConnectionsController < ApplicationController
    # Deliberately unauthenticated. The OAuth flow has no Devise session;
    # authorization comes from the connect intent plus the handoff token,
    # re-verified in the callback. Adding authenticate_user! would bounce
    # the callback to staff sign-in.

    def new
      render_google_connect_result(:service_unavailable, t("integrations.google_connections.unavailable"))
    end

    # Narrow OAuth transport. Authenticates nobody and establishes nothing —
    # it renders a CSRF-protected form for a browser that already holds the
    # connect intent. The bound bearer initiation determines the intended
    # account; an unrelated Devise current_user is never an identity fallback.
    def transport
      token = params[:token]
      intent = Integrations::Google::ConnectIntent.new(session)
      unless intent.valid?(token)
        return render_google_connect_result(:forbidden, t("integrations.google_connections.invalid"))
      end

      @token = token
      render :transport, layout: false
    end

    def create
      token = omniauth_handoff_token
      intent = Integrations::Google::ConnectIntent.new(session)
      auth = request.env["omniauth.auth"]

      unless intent.valid?(token) && auth.present?
        return render_google_connect_result(:forbidden, t("integrations.google_connections.invalid"))
      end

      # Guard 2 is the TOCTOU path: intent.valid? already established
      # user.active? and the identity match. The only conjunct that can
      # independently fail here is ConnectionToken.claim losing a concurrent
      # race, which a single-threaded request spec cannot reach.
      user = ConnectionToken.claim(token, purpose: ConnectionToken::GOOGLE)
      unless user && user.id == intent.user.id && user.active?
        return render_google_connect_result(:forbidden, t("integrations.google_connections.invalid"))
      end

      intent.clear

      Integrations::Google::ConnectAccount.call(user: user, auth: auth)
      render_google_connect_result(:ok, t("integrations.google_connections.completed"))
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error("[integrations.google] connect failed: #{error.class}")
      render_google_connect_result(:internal_server_error, t("integrations.google_connections.completion_failed"))
    end

    def failure
      intent = Integrations::Google::ConnectIntent.new(session)
      if params[:message] == "access_denied" && intent.valid?(intent.raw_token)
        retry_url = google_oauth_connect_path(token: intent.raw_token)
        render_google_connect_result(:ok, t("integrations.google_connections.not_completed"), retry_url: retry_url)
      else
        render_google_connect_result(:forbidden, t("integrations.google_connections.invalid"))
      end
    end

    private

    def omniauth_handoff_token
      restored = request.env["omniauth.params"] || {}
      restored["token"] || restored[:token]
    end

    def render_google_connect_result(status, message, retry_url: nil)
      @message = message
      @retry_url = retry_url
      render :result, layout: false, status: status
    end
  end
end
