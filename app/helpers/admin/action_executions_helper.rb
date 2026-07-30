module Admin
  module ActionExecutionsHelper
    STATUS_BADGE_CLASSES = {
      "succeeded" => "bg-emerald-50 text-emerald-700",
      "failed" => "bg-rose-50 text-rose-700",
      "pending" => "bg-amber-50 text-amber-700",
      "processing" => "bg-amber-50 text-amber-700",
      "cancelled" => "bg-slate-100 text-slate-600"
    }.freeze

    def action_status_badge_class(status)
      STATUS_BADGE_CLASSES.fetch(status.to_s, "bg-slate-100 text-slate-600")
    end
  end
end
