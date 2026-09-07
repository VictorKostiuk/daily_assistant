require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  describe "GET /admin/users" do
    it "redirects unauthenticated visitors to sign in" do
      get admin_users_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns 403 for a signed-in member with no redirect" do
      sign_in create(:user)

      get admin_users_path

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Location"]).to be_blank
    end

    it "returns 403 for an admin demoted after login who still holds a session" do
      admin = create(:user, :admin)
      sign_in admin
      admin.update!(role: :member)

      get admin_users_path

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Location"]).to be_blank
    end

    it "allows a signed-in admin and lists users" do
      admin = create(:user, :admin)
      member = create(:user, first_name: "Grace", last_name: "Hopper")
      sign_in admin

      get admin_users_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member.email)
    end
  end

  describe "GET /admin/users/:id" do
    it "shows the user's action history" do
      admin = create(:user, :admin)
      member = create(:user)
      create(:action_execution, user: member, action_type: "setup_event", status: :succeeded)
      sign_in admin

      get admin_user_path(member)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("setup_event")
    end

    it "returns 404 for a nonexistent user" do
      sign_in create(:user, :admin)

      get admin_user_path(id: -1)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/users/:id" do
    it "denies a signed-in member" do
      sign_in create(:user)
      member = create(:user)

      patch admin_user_path(member), params: { user: { role: "admin" } }

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Location"]).to be_blank
      expect(member.reload.role).to eq("member")
    end

    it "updates the target user's role and status" do
      admin = create(:user, :admin)
      member = create(:user)
      sign_in admin

      patch admin_user_path(member), params: { user: { role: "moderator", status: "suspended" } }

      expect(response).to redirect_to(admin_user_path(member))
      member.reload
      expect(member.role).to eq("moderator")
      expect(member.status).to eq("suspended")
    end

    it "records an audit log entry with the actor, target, and changed fields" do
      admin = create(:user, :admin)
      member = create(:user)
      sign_in admin

      expect {
        patch admin_user_path(member), params: { user: { role: "moderator" } }
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.actor).to eq(admin)
      expect(log.target_user).to eq(member)
      expect(log.changes_data["role"]).to eq(%w[member moderator])
    end

    it "does not create an audit log entry when nothing actually changes" do
      admin = create(:user, :admin)
      member = create(:user)
      sign_in admin

      expect {
        patch admin_user_path(member), params: { user: { role: member.role, status: member.status } }
      }.not_to change(AuditLog, :count)
    end

    it "prevents an admin from changing their own role or status" do
      admin = create(:user, :admin)
      sign_in admin

      patch admin_user_path(admin), params: { user: { role: "member" } }

      expect(admin.reload.role).to eq("admin")
      expect(response).to redirect_to(admin_user_path(admin))
    end

    it "records the actor's ip address and user agent on the audit log entry" do
      admin = create(:user, :admin)
      member = create(:user)
      sign_in admin

      patch admin_user_path(member), params: { user: { role: "moderator" } }, headers: { "User-Agent" => "RSpec Test Agent" }

      log = AuditLog.last
      expect(log.ip_address).to be_present
      expect(log.user_agent).to eq("RSpec Test Agent")
    end

    it "reports an error and changes nothing for a crafted invalid role value, instead of a raw 500" do
      admin = create(:user, :admin)
      member = create(:user)
      sign_in admin

      patch admin_user_path(member), params: { user: { role: "superadmin" } }

      expect(response).to redirect_to(admin_user_path(member))
      expect(member.reload.role).to eq("member")
      expect(AuditLog.count).to eq(0)
    end

    it "rolls back the role change if writing the audit log fails" do
      admin = create(:user, :admin)
      member = create(:user)
      sign_in admin
      allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))

      patch admin_user_path(member), params: { user: { role: "moderator" } }

      expect(response).to have_http_status(422)
      expect(member.reload.role).to eq("member")
    end
  end
end
