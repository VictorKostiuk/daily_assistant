require "rails_helper"

RSpec.describe "Password recovery", type: :request do
  let(:password) { "password123" }
  let(:user) { create(:user, password: password) }

  def issue_token_for(user)
    ApiToken.issue!(user: user).first
  end

  def raw_reset_token_for(user)
    user.send_reset_password_instructions
  end

  describe "Core-hosted reset form" do
    it "renders a narrow token-bearing form without Devise member-account links" do
      raw = raw_reset_token_for(user)

      get edit_auth_password_path(reset_password_token: raw)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("reset_password_token")
      expect(response.body).to include("Choose a new password")
      expect(response.body).to include("Set a fresh password for your account.")
      expect(response.body).to include("New password")
      expect(response.body).to include("#{Devise.password_length.min} characters minimum")
      expect(response.body).to include("Confirm new password")
      expect(response.body).to include("Change password")
      expect(response.body).not_to include("/users/sign_up")
      expect(response.body).not_to include("/users/password/new")
    end

    it "completes a reset over HTML, revokes API tokens, and issues no session" do
      token = issue_token_for(user)
      raw = raw_reset_token_for(user)

      put auth_password_path, params: {
        reset_password_token: raw,
        password: "new-password-1",
        password_confirmation: "new-password-1"
      }

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.valid_password?("new-password-1")).to be(true)
      expect(ApiToken.find_by!(token_digest: ApiToken.digest(token)).revoked_at).to be_present
      expect(request.env["warden"].user).to be_nil

      get admin_users_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  it "completes recovery requested via the API without a session or a new token" do
    ActionMailer::Base.deliveries.clear
    existing_token = issue_token_for(user)

    post "/api/v1/auth/password", params: { email: user.email }, as: :json
    expect(response).to have_http_status(:accepted)

    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    html = mail.html_part&.decoded || mail.body.decoded
    href = Nokogiri::HTML(html).at_css("a")&.[]("href")
    expect(href).to include("/auth/password/edit")
    token_param = Rack::Utils.parse_query(URI.parse(href).query).fetch("reset_password_token")

    get edit_auth_password_path(reset_password_token: token_param)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Choose a new password")
    expect(response.body).to include("Change password")

    expect {
      put auth_password_path, params: {
        reset_password_token: token_param,
        password: "new-password-1",
        password_confirmation: "new-password-1"
      }
    }.not_to change(ApiToken, :count)

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.valid_password?("new-password-1")).to be(true)
    expect(ApiToken.find_by!(token_digest: ApiToken.digest(existing_token)).revoked_at).to be_present
    expect(user.api_tokens.where(revoked_at: nil)).to be_empty
    expect(request.env["warden"].user).to be_nil

    get admin_users_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "lets staff recover a password through the same path" do
    admin = create(:user, :admin, password: password)
    raw = raw_reset_token_for(admin)

    put auth_password_path, params: {
      reset_password_token: raw,
      password: "staff-password-1",
      password_confirmation: "staff-password-1"
    }

    expect(response).to redirect_to(new_user_session_path)
    expect(admin.reload.valid_password?("staff-password-1")).to be(true)

    post user_session_path, params: { user: { email: admin.email, password: "staff-password-1" } }
    expect(response).to redirect_to(root_path)
    get admin_users_path
    expect(response).to have_http_status(:ok)
  end
end
