class PlanLimit < ApplicationRecord
  enum :period, {
    lifetime: 0,
    daily: 1,
    monthly: 2
  }
end
