require "rails_helper"

RSpec.describe "API v1 auth", type: :request do
  def json
    JSON.parse(response.body)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def issue_token_for(user)
    ApiToken.issue!(user: user).first
  end

  def error_envelope(code:, message:, details: {})
    { "error" => { "code" => code, "message" => message, "details" => details } }
  end

  def expect_unauthorized
    expect(response).to have_http_status(:unauthorized)
    expect(json).to eq(error_envelope(code: "unauthorized", message: "Unauthorized"))
  end

  def expect_validation_error(details: nil)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("validation_error")
    expect(json.dig("error", "message")).to eq("Request is invalid")
    expect(json.fetch("error")).to have_key("details")
    expect(json.dig("error", "details")).to eq(details) if details
  end

  let(:password) { "password123" }
  let(:user) { create(:user, password: password) }

  describe "POST /api/v1/auth/signup" do
    let(:valid_params) do
      {
        email: "grace@example.com",
        password: password,
        password_confirmation: password,
        first_name: "Grace",
        last_name: "Hopper",
        time_zone: "Europe/Rome",
        locale: "en"
      }
    end

    it "creates an active member and returns the /me fields without a token" do
      expect {
        post "/api/v1/auth/signup", params: valid_params, as: :json
      }.to change(User, :count).by(1)

      created = User.find_by!(email: "grace@example.com")
      expect(created.role).to eq("member")
      expect(created.status).to eq("active")
      expect(created.api_tokens).to be_empty

      expect(response).to have_http_status(:created)
      expect(json).to eq(
        "id" => created.id,
        "email" => "grace@example.com",
        "first_name" => "Grace",
        "last_name" => "Hopper",
        "time_zone" => "Europe/Rome",
        "locale" => "en",
        "role" => "member",
        "status" => "active"
      )
      expect(json).not_to have_key("token")
    end

    it "does not honour role, status, or id in the input" do
      existing = create(:user)

      post "/api/v1/auth/signup", params: valid_params.merge(
        id: existing.id,
        role: "admin",
        status: "suspended",
        encrypted_password: "forged"
      ), as: :json

      created = User.find_by!(email: "grace@example.com")
      expect(response).to have_http_status(:created)
      expect(created.id).not_to eq(existing.id)
      expect(created.role).to eq("member")
      expect(created.status).to eq("active")
      expect(created.valid_password?(password)).to be(true)
    end

    it "rejects a present non-blank invalid time_zone without creating a user" do
      expect {
        post "/api/v1/auth/signup", params: valid_params.merge(time_zone: "Not/AZone"), as: :json
      }.not_to change(User, :count)

      expect_validation_error(details: { "time_zone" => [ "is invalid" ] })
    end

    it "rejects a non-string time_zone without creating a user" do
      expect {
        post "/api/v1/auth/signup", params: valid_params.merge(time_zone: 1), as: :json
      }.not_to change(User, :count)

      expect_validation_error(details: { "time_zone" => [ "is invalid" ] })
    end

    it "validates the merged time_zone that signup actually persists, with query overriding body" do
      expect {
        post "/api/v1/auth/signup?time_zone=#{CGI.escape("Not/AZone")}",
             params: valid_params.merge(email: "query-only-invalid@example.com").except(:time_zone),
             as: :json
      }.not_to change(User, :count)
      expect_validation_error(details: { "time_zone" => [ "is invalid" ] })
      expect(User.find_by(email: "query-only-invalid@example.com")).to be_nil

      expect {
        post "/api/v1/auth/signup?time_zone=#{CGI.escape("Not/AZone")}",
             params: valid_params.merge(email: "query-invalid-body-valid@example.com", time_zone: "Europe/Rome"),
             as: :json
      }.not_to change(User, :count)
      expect_validation_error(details: { "time_zone" => [ "is invalid" ] })
      expect(User.find_by(email: "query-invalid-body-valid@example.com")).to be_nil

      expect {
        post "/api/v1/auth/signup?time_zone=#{CGI.escape("Europe/Paris")}",
             params: valid_params.merge(email: "query-valid-body-invalid@example.com", time_zone: "Not/AZone"),
             as: :json
      }.to change(User, :count).by(1)
      expect(response).to have_http_status(:created)
      created = User.find_by!(email: "query-valid-body-invalid@example.com")
      expect(created.time_zone).to eq("Europe/Paris")
    end

    it "still rejects a wrong-type body time_zone and still drops unknown keys" do
      expect {
        post "/api/v1/auth/signup",
             params: valid_params.merge(email: "hash-zone@example.com", time_zone: { "name" => "Europe/Rome" }),
             as: :json
      }.not_to change(User, :count)
      expect_validation_error(details: { "time_zone" => [ "is invalid" ] })
      expect(User.find_by(email: "hash-zone@example.com")).to be_nil

      existing = create(:user)
      post "/api/v1/auth/signup", params: valid_params.merge(
        email: "extras-still-dropped@example.com",
        id: existing.id,
        role: "admin",
        status: "suspended"
      ), as: :json
      created = User.find_by!(email: "extras-still-dropped@example.com")
      expect(response).to have_http_status(:created)
      expect(created.id).not_to eq(existing.id)
      expect(created.role).to eq("member")
      expect(created.status).to eq("active")
    end

    it "accepts an absent or blank time_zone and stores it without normalising blank to nil" do
      post "/api/v1/auth/signup", params: valid_params.except(:time_zone), as: :json
      expect(response).to have_http_status(:created)
      expect(User.find_by!(email: "grace@example.com").time_zone).to be_nil

      post "/api/v1/auth/signup", params: valid_params.merge(
        email: "blank-zone@example.com",
        time_zone: ""
      ), as: :json
      expect(response).to have_http_status(:created)
      created = User.find_by!(email: "blank-zone@example.com")
      expect(created.time_zone).to eq("")
      expect(json["time_zone"]).to eq("")
    end

    it "rejects invalid input with the documented error shape" do
      post "/api/v1/auth/signup", params: {
        email: "not-an-email",
        password: "1",
        password_confirmation: "2",
        first_name: "G",
        last_name: ""
      }, as: :json

      expect_validation_error
      expect(json.dig("error", "details")).to include("email", "password", "first_name", "last_name")
    end

    it "returns 422 for a missing body" do
      post "/api/v1/auth/signup", as: :json
      expect_validation_error
    end

    it "treats mixed-case and padded emails as the same identity" do
      post "/api/v1/auth/signup", params: valid_params.merge(email: "  Foo@Example.COM "), as: :json

      expect(response).to have_http_status(:created)
      expect(User.find_by!(email: "foo@example.com")).to be_present

      post "/api/v1/auth/login", params: { email: "  FOO@example.com ", password: password }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/auth/login" do
    it "returns a working bearer token whose expires_at comes from the persisted row" do
      post "/api/v1/auth/login", params: { email: user.email, password: password }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.keys).to contain_exactly("token", "token_type", "expires_at")
      expect(json["token_type"]).to eq("Bearer")
      expect(json["token"]).to be_present

      record = ApiToken.find_by!(token_digest: ApiToken.digest(json["token"]))
      expect(json["expires_at"]).to eq(record.expires_at.iso8601)
      expect(record.user).to eq(user)

      get "/api/v1/me", headers: bearer(json["token"])
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(user.id)
    end

    it "returns identical 401 responses for unknown email, wrong password, and inactive accounts" do
      create(:user, email: "taken@example.com", password: password, status: :suspended)

      payloads = [
        { email: "nobody@example.com", password: password },
        { email: user.email, password: "wrong-password" },
        { email: "taken@example.com", password: password }
      ]

      bodies = payloads.map do |params|
        post "/api/v1/auth/login", params: params, as: :json
        expect_unauthorized
        response.body
      end

      expect(bodies.uniq.size).to eq(1)
    end

    %w[suspended blocked pending].each do |status|
      it "refuses a #{status} user and does not create a token row" do
        user.update!(status: status)

        expect {
          post "/api/v1/auth/login", params: { email: user.email, password: password }, as: :json
        }.not_to change(ApiToken, :count)

        expect_unauthorized
      end

      it "compares a password digest for a #{status} user even when the password is correct" do
        user.update!(status: status)
        expect(Devise::Encryptor).to receive(:compare).and_call_original

        post "/api/v1/auth/login", params: { email: user.email, password: password }, as: :json

        expect_unauthorized
      end
    end

    it "returns 422 for missing parameters" do
      post "/api/v1/auth/login", params: {}, as: :json
      expect_validation_error
    end

    it "returns 422 for a malformed JSON body" do
      post "/api/v1/auth/login",
        params: "{",
        headers: { "Content-Type" => "application/json" }

      expect_validation_error
    end

    it "does not accept a session cookie in place of the password" do
      sign_in user

      post "/api/v1/auth/login", params: { email: user.email }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    it "revokes the presented token so the same token then fails /me" do
      token = issue_token_for(user)

      delete "/api/v1/auth/logout", headers: bearer(token)
      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
      expect(ApiToken.find_by!(token_digest: ApiToken.digest(token)).revoked_at).to be_present

      get "/api/v1/me", headers: bearer(token)
      expect_unauthorized
    end

    it "returns 401 on a second call with the now-revoked token" do
      token = issue_token_for(user)

      delete "/api/v1/auth/logout", headers: bearer(token)
      delete "/api/v1/auth/logout", headers: bearer(token)
      expect_unauthorized
    end

    it "does not authenticate from a Devise session cookie without a bearer token" do
      sign_in user

      delete "/api/v1/auth/logout"
      expect_unauthorized
    end
  end

  describe "POST /api/v1/auth/password" do
    before { ActionMailer::Base.deliveries.clear }

    it "returns the same 202 body for a known and an unknown email and never includes the reset token" do
      post "/api/v1/auth/password", params: { email: user.email }, as: :json
      known = [ response.status, response.body ]

      post "/api/v1/auth/password", params: { email: "nobody@example.com" }, as: :json
      unknown = [ response.status, response.body ]

      expect(known).to eq(unknown)
      expect(response).to have_http_status(:accepted)
      expect(json).to eq({})
      expect(response.body).not_to include("reset_password_token")
      expect(response.body).not_to include(user.reload.reset_password_token.to_s) if user.reset_password_token
    end

    it "emails a Core-hosted reset link for a known account and never puts the token in the JSON" do
      post "/api/v1/auth/password", params: { email: user.email }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ user.email ])
      expect(mail.body.encoded).to include("auth/password/edit")
      expect(mail.body.encoded).to include("reset_password_token=")
      expect(json).not_to have_key("reset_password_token")
      expect(json).not_to have_key("token")
    end

    it "returns 422 for a missing body" do
      post "/api/v1/auth/password", as: :json
      expect_validation_error
    end

    it "returns 202 when delivering the reset mail raises" do
      address = user.email
      delivery_class = Class.new do
        define_method(:initialize) { |*| }
        define_method(:deliver!) do |*|
          raise Net::SMTPServerBusy, "550 <#{address}> mailbox unavailable"
        end
      end
      ActionMailer::Base.add_delivery_method :raising, delivery_class
      previous = ActionMailer::Base.delivery_method
      ActionMailer::Base.delivery_method = :raising

      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      previous_logger = Rails.logger
      Rails.logger = logger

      begin
        post "/api/v1/auth/password", params: { email: user.email }, as: :json

        expect(response).to have_http_status(:accepted)
        expect(json).to eq({})
        expect(io.string).to include("Net::SMTPServerBusy")
        expect(io.string).not_to include(user.email)

        post "/api/v1/auth/password", params: { email: "nobody@example.com" }, as: :json
        expect(response).to have_http_status(:accepted)
        expect(json).to eq({})
      ensure
        Rails.logger = previous_logger
        ActionMailer::Base.delivery_method = previous
      end
    end
  end

  describe "PUT /api/v1/auth/password" do
    def raw_reset_token_for(user)
      user.send_reset_password_instructions
    end

    it "resets the password, revokes existing API tokens, and issues neither a session nor a bearer token" do
      token = issue_token_for(user)
      raw = raw_reset_token_for(user)

      put "/api/v1/auth/password", params: {
        reset_password_token: raw,
        password: "new-password-1",
        password_confirmation: "new-password-1"
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).not_to have_key("token")
      expect(user.reload.valid_password?("new-password-1")).to be(true)
      expect(ApiToken.find_by!(token_digest: ApiToken.digest(token)).revoked_at).to be_present

      get "/api/v1/me", headers: bearer(token)
      expect_unauthorized

      get admin_users_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "leaves existing tokens working when the reset token is invalid" do
      token = issue_token_for(user)

      expect {
        put "/api/v1/auth/password", params: {
          reset_password_token: "not-a-real-token",
          password: "new-password-1",
          password_confirmation: "new-password-1"
        }, as: :json
      }.not_to change { ApiToken.find_by!(token_digest: ApiToken.digest(token)).reload.revoked_at }

      expect_validation_error
      expect(user.reload.valid_password?(password)).to be(true)

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end

    it "leaves existing tokens working when the reset token is expired" do
      token = issue_token_for(user)
      raw = raw_reset_token_for(user)
      user.update!(reset_password_sent_at: 7.hours.ago)

      expect {
        put "/api/v1/auth/password", params: {
          reset_password_token: raw,
          password: "new-password-1",
          password_confirmation: "new-password-1"
        }, as: :json
      }.not_to change { ApiToken.find_by!(token_digest: ApiToken.digest(token)).reload.revoked_at }

      expect_validation_error
      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end

    it "does not accept a session cookie in place of the reset token" do
      token = issue_token_for(user)
      sign_in user

      put "/api/v1/auth/password", params: {
        password: "new-password-1",
        password_confirmation: "new-password-1"
      }, as: :json

      expect_validation_error
      expect(user.reload.valid_password?(password)).to be(true)
      expect(ApiToken.find_by!(token_digest: ApiToken.digest(token)).revoked_at).to be_nil
    end
  end

  describe "throttling" do
    it "uses a cache store whose increment returns an Integer" do
      expect(Rails.cache.increment("api-auth-throttle-store-probe")).to be_a(Integer)
    end

    it "rejects the 11th login from the same IP within 3 minutes" do
      10.times do
        post "/api/v1/auth/login", params: { email: user.email, password: "wrong" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      post "/api/v1/auth/login", params: { email: user.email, password: "wrong" }, as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(json).to eq(error_envelope(code: "too_many_requests", message: "Too many requests"))
    end

    it "rejects the 6th signup from the same IP within an hour" do
      5.times do |i|
        post "/api/v1/auth/signup", params: {
          email: "signup#{i}@example.com",
          password: password,
          password_confirmation: password,
          first_name: "Ada",
          last_name: "Lovelace"
        }, as: :json
        expect(response).to have_http_status(:created)
      end

      post "/api/v1/auth/signup", params: {
        email: "signup-overflow@example.com",
        password: password,
        password_confirmation: password,
        first_name: "Ada",
        last_name: "Lovelace"
      }, as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(json.dig("error", "code")).to eq("too_many_requests")
    end

    it "rejects the 6th password-reset request from the same IP within an hour" do
      5.times do |i|
        post "/api/v1/auth/password", params: { email: "reset#{i}@example.com" }, as: :json
        expect(response).to have_http_status(:accepted)
      end

      post "/api/v1/auth/password", params: { email: "reset-overflow@example.com" }, as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(json.dig("error", "code")).to eq("too_many_requests")
    end
  end
end
