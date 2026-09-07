class AdminPolicy < ApplicationPolicy
  def access?
    # Acting user must be an active admin. Target status is not consulted:
    # staff must still be able to view suspended members.
    user&.active? && user&.admin?
  end
end
