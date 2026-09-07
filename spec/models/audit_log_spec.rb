require "rails_helper"

RSpec.describe AuditLog, type: :model do
  it "is valid with an actor, target user, and action" do
    admin = create(:user, :admin)
    member = create(:user)

    log = AuditLog.new(actor: admin, target_user: member, auditable: member, action: "user.updated", changes_data: { "role" => %w[member admin] })

    expect(log).to be_valid
  end
end
