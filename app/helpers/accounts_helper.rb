module AccountsHelper
  GOOGLE_BADGE_CLASSES = {
    connected: "bg-emerald-100 text-emerald-800",
    reconnect_required: "bg-rose-50 text-rose-700",
    not_connected: "bg-amber-50 text-amber-700"
  }.freeze

  def external_redirect_form_options
    { data: { turbo: false } }
  end

  def connection_cards
    [
      telegram_connection_card,
      google_connection_card,
      placeholder_connection_card(:reminders),
      placeholder_connection_card(:digest)
    ]
  end

  def google_connection_state
    return :connected if @google_integration&.connected?
    return :reconnect_required if @google_integration&.reconnect_required?

    :not_connected
  end

  def google_services
    Integrations::Google.granted_services(@google_integration&.scopes)
  end

  def google_service_label(service)
    t("accounts.show.google.services.#{service}", default: service.to_s.humanize)
  end

  private

  def telegram_connection_card
    connected = @telegram_account.present?

    card = {
      title: t("accounts.show.services.cards.telegram.title"),
      description: t("accounts.show.services.cards.telegram.description"),
      status: t("accounts.show.services.cards.telegram.#{connected ? "connected" : "not_connected"}"),
      badge_class: connected ? "bg-emerald-100 text-emerald-800" : "bg-amber-50 text-amber-700"
    }

    return card.merge(cta: t("accounts.show.services.cards.telegram.cta"), path: "#telegram-integration") if connected

    card.merge(
      cta: t("accounts.show.services.cards.telegram.connect"),
      path: integrations_telegram_connection_path,
      method: :post,
      form: external_redirect_form_options
    )
  end

  def google_connection_card
    state = google_connection_state

    card = {
      title: t("accounts.show.services.cards.google.title"),
      description: t("accounts.show.services.cards.google.description"),
      status: t("accounts.show.services.cards.google.statuses.#{state}"),
      badge_class: GOOGLE_BADGE_CLASSES.fetch(state)
    }

    return card.merge(cta: t("accounts.show.services.cards.google.manage"), path: "#google-integration") if state == :connected

    card.merge(
      cta: t("accounts.show.services.cards.google.#{state == :reconnect_required ? "reconnect" : "connect"}"),
      path: google_oauth_request_path,
      method: :post,
      form: external_redirect_form_options
    )
  end

  def placeholder_connection_card(key)
    {
      title: t("accounts.show.services.cards.#{key}.title"),
      description: t("accounts.show.services.cards.#{key}.description"),
      status: t("accounts.show.services.cards.#{key}.status"),
      cta: t("accounts.show.services.cards.#{key}.cta"),
      path: "#",
      badge_class: "bg-slate-100 text-slate-600"
    }
  end
end
