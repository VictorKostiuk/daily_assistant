module AccountsHelper
  def connection_cards
    [
      telegram_connection_card,
      placeholder_connection_card(:calendar),
      placeholder_connection_card(:reminders),
      placeholder_connection_card(:digest)
    ]
  end

  private

  def telegram_connection_card
    connected = @telegram_account.present?

    {
      title: t("accounts.show.services.cards.telegram.title"),
      description: t("accounts.show.services.cards.telegram.description"),
      status: t("accounts.show.services.cards.telegram.#{connected ? "connected" : "not_connected"}"),
      cta: t("accounts.show.services.cards.telegram.cta"),
      path: account_path,
      badge_class: connected ? "bg-emerald-100 text-emerald-800" : "bg-amber-50 text-amber-700"
    }
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
