require "rails_helper"

RSpec.describe "Staff HTML sessions", type: :request do
  let(:password) { "password123" }

  it "renders the sign-in page" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in")
    expect(response.body).not_to include("/users/sign_up")
    expect(response.body).not_to include("/users/password/new")
  end

  it "lets an active admin sign in through the HTML session path" do
    admin = create(:user, :admin, password: password)

    post user_session_path, params: { user: { email: admin.email, password: password } }

    expect(response).to redirect_to(root_path)
    get admin_users_path
    expect(response).to have_http_status(:ok)
  end

  it "refuses a member credential on the HTML session path" do
    member = create(:user, password: password)

    post user_session_path, params: { user: { email: member.email, password: password } }

    expect(response).not_to redirect_to(root_path)
    get admin_users_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "denies an already-issued session after the acting user's status changes" do
    admin = create(:user, :admin, password: password)
    sign_in admin
    admin.suspended!

    get admin_users_path

    expect(response).to have_http_status(:redirect)
    expect(response).not_to have_http_status(:ok)
  end

  it "denies an already-issued session after the acting user's role changes" do
    admin = create(:user, :admin, password: password)
    sign_in admin
    admin.update!(role: :member)

    get admin_users_path

    expect(response).to have_http_status(:forbidden)
    expect(response.headers["Location"]).to be_blank
  end

  it "lets staff view a suspended target user" do
    admin = create(:user, :admin)
    suspended = create(:user, status: :suspended, first_name: "Nico", last_name: "Suspended")
    sign_in admin

    get admin_user_path(suspended)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nico")
    expect(response.body).to include(suspended.email)
  end

  it "lets staff sign out through the HTML session path" do
    admin = create(:user, :admin, password: password)
    sign_in admin

    delete destroy_user_session_path

    expect(response).to redirect_to(root_path)
    get admin_users_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "rejects the 11th HTML sign-in from the same IP within 3 minutes" do
    10.times do
      post user_session_path, params: { user: { email: "nobody@example.com", password: "wrong" } }
      expect(response).not_to have_http_status(:too_many_requests)
    end

    post user_session_path, params: { user: { email: "nobody@example.com", password: "wrong" } }
    expect(response).to have_http_status(:too_many_requests)
  end
end
