require "rails_helper"

RSpec.describe "API v1 integrations", type: :request do
  include ActiveSupport::Testing::TimeHelpers
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

  def with_env(name, value)
    previous = ENV[name]
    if value.nil?
      ENV.delete(name)
    else
      ENV[name] = value
    end
    yield
  ensure
    if previous.nil?
      ENV.delete(name)
    else
      ENV[name] = previous
    end
  end

  let(:user) { create(:user) }
  let(:token) { issue_token_for(user) }

  describe "GET /api/v1/integrations" do
    it "returns disconnected Google and Telegram when the user has no rows" do
      expect {
        get "/api/v1/integrations", headers: bearer(token)
      }.not_to change(IntegrationProvider, :count)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        "google" => { "connected" => false, "reconnect_required" => false },
        "telegram" => { "connected" => false }
      )
    end

    it "maps a connected Google row and a Telegram account" do
      create(
        :user_integration,
        user: user,
        status: :connected,
        access_token: "leaked-access-token-UNIQUE123",
        refresh_token: "leaked-refresh-token-UNIQUE456",
        external_account_id: "google-sub-UNIQUE789"
      )
      create(:telegram_account, user: user)

      get "/api/v1/integrations", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        "google" => { "connected" => true, "reconnect_required" => false },
        "telegram" => { "connected" => true }
      )
      expect(response.body).not_to include("leaked-access-token-UNIQUE123")
      expect(response.body).not_to include("leaked-refresh-token-UNIQUE456")
      expect(response.body).not_to include("google-sub-UNIQUE789")
    end

    it "maps revoked, expired, and error Google rows as reconnect_required" do
      integration = create(:user_integration, user: user, status: :revoked)

      get "/api/v1/integrations", headers: bearer(token)
      expect(json["google"]).to eq("connected" => false, "reconnect_required" => true)

      integration.update!(status: :expired)
      get "/api/v1/integrations", headers: bearer(token)
      expect(json["google"]).to eq("connected" => false, "reconnect_required" => true)

      integration.update!(status: :error)
      get "/api/v1/integrations", headers: bearer(token)
      expect(json["google"]).to eq("connected" => false, "reconnect_required" => true)
    end

    it "does not create a provider row and never calls IntegrationProvider.google" do
      allow(IntegrationProvider).to receive(:google).and_call_original

      get "/api/v1/integrations", headers: bearer(token)

      expect(IntegrationProvider).not_to have_received(:google)
    end

    it "does not expose another user's integrations" do
      other = create(:user)
      create(:user_integration, user: other, status: :connected)
      create(:telegram_account, user: other)

      get "/api/v1/integrations", headers: bearer(token)

      expect(json).to eq(
        "google" => { "connected" => false, "reconnect_required" => false },
        "telegram" => { "connected" => false }
      )
    end

    it "returns 401 without a bearer" do
      get "/api/v1/integrations"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(error_envelope(code: "unauthorized", message: "Unauthorized"))
    end
  end

  describe "POST /api/v1/integrations/telegram/connect" do
    it "returns a t.me deep link and issues a telegram connection token" do
      with_env("TELEGRAM_BOT_USERNAME", "daily_test_bot") do
        expect {
          post "/api/v1/integrations/telegram/connect", headers: bearer(token)
        }.to change(ConnectionToken, :count).by(1)

        expect(response).to have_http_status(:ok)
        start_token = Rack::Utils.parse_query(URI.parse(json.fetch("url")).query).fetch("start")
        expect(json).to eq("url" => "https://t.me/daily_test_bot?start=#{start_token}")
        record = ConnectionToken.find_by!(
          token_digest: ConnectionToken.digest(start_token),
          purpose: ConnectionToken::TELEGRAM
        )
        expect(record.user).to eq(user)
        expect(record.used_at).to be_nil
      end
    end

    it "returns 503 integration_unavailable and issues no token when the bot username is blank" do
      with_env("TELEGRAM_BOT_USERNAME", nil) do
        expect {
          post "/api/v1/integrations/telegram/connect", headers: bearer(token)
        }.not_to change(ConnectionToken, :count)

        expect(response).to have_http_status(:service_unavailable)
        expect(json).to eq(error_envelope(code: "integration_unavailable", message: "Integration is unavailable"))
      end
    end
  end

  describe "DELETE /api/v1/integrations/telegram" do
    it "destroys the caller's Telegram account and returns 204" do
      create(:telegram_account, user: user)

      delete "/api/v1/integrations/telegram", headers: bearer(token)

      expect(response).to have_http_status(:no_content)
      expect(user.reload.telegram_account).to be_nil
    end

    it "is idempotent when already disconnected" do
      delete "/api/v1/integrations/telegram", headers: bearer(token)
      expect(response).to have_http_status(:no_content)

      delete "/api/v1/integrations/telegram", headers: bearer(token)
      expect(response).to have_http_status(:no_content)
    end

    it "does not destroy another user's Telegram account" do
      other = create(:user)
      other_account = create(:telegram_account, user: other)

      delete "/api/v1/integrations/telegram", headers: bearer(token)

      expect(response).to have_http_status(:no_content)
      expect(TelegramAccount.find_by(id: other_account.id)).to be_present
    end
  end

  describe "POST /api/v1/integrations/google/connect" do
    it "stores a session intent and returns a launch URL whose query param is named token" do
      expect {
        post "/api/v1/integrations/google/connect", headers: bearer(token)
      }.to change(ConnectionToken, :count).by(1)

      expect(response).to have_http_status(:ok)
      launch = URI.parse(json.fetch("url"))
      handoff = Rack::Utils.parse_query(launch.query).fetch("token")
      expect(json.keys).to eq([ "url" ])
      expect(launch.path).to eq("/auth/google_oauth2/connect")
      expect(Rack::Utils.parse_query(launch.query).keys).to eq([ "token" ])

      record = ConnectionToken.find_by!(
        token_digest: ConnectionToken.digest(handoff),
        purpose: ConnectionToken::GOOGLE
      )
      expect(record.user).to eq(user)
      expect(session[:google_connect]).to include("user_id" => user.id, "token" => handoff)
    end

    it "issues no Google handoff when the bearer user is not active" do
      user.suspended!

      expect {
        post "/api/v1/integrations/google/connect", headers: bearer(token)
      }.not_to change(ConnectionToken, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(session[:google_connect]).to be_blank
    end

    it "returns 503 integration_unavailable and issues no handoff when Google is unconfigured" do
      allow(Integrations::Google).to receive(:settings).and_return(
        double(client_id: nil, client_secret: nil)
      )

      expect {
        post "/api/v1/integrations/google/connect", headers: bearer(token)
      }.not_to change(ConnectionToken, :count)

      expect(response).to have_http_status(:service_unavailable)
      expect(json).to eq(error_envelope(code: "integration_unavailable", message: "Integration is unavailable"))
    end

    it "rejects a disallowed-origin POST before inherited authentication writes" do
      freeze_time do
        post "/api/v1/integrations/google/connect", headers: bearer(token)
        expect(response).to have_http_status(:ok)
        existing_token = Rack::Utils.parse_query(URI.parse(json.fetch("url")).query).fetch("token")
        existing_digest = ConnectionToken.digest(existing_token)
        existing_intent = session[:google_connect].dup

        api_token = ApiToken.find_by!(token_digest: ApiToken.digest(token))
        stamped = 1.hour.ago
        api_token.update_column(:last_used_at, stamped)

        expect {
          post "/api/v1/integrations/google/connect",
               headers: bearer(token).merge("Origin" => "https://evil.example")
        }.not_to change(ConnectionToken, :count)

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(error_envelope(code: "origin_not_allowed", message: "Origin is not allowed"))
        expect(api_token.reload.last_used_at).to eq(stamped)
        expect(session[:google_connect]).to eq(existing_intent)
        expect(ConnectionToken.find_by!(token_digest: existing_digest).used_at).to be_nil
        expect(response.headers["Access-Control-Allow-Origin"]).to be_blank
      end
    end

    it "allows a trusted sibling HTTPS origin and echoes it after the allowlist check" do
      with_env("GOOGLE_CONNECT_ORIGINS", "https://life.example.test") do
        post "/api/v1/integrations/google/connect",
             headers: bearer(token).merge("Origin" => "https://life.example.test")

        expect(response).to have_http_status(:ok)
        expect(json).to have_key("url")
        expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://life.example.test")
        expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
        expect(response.headers["Access-Control-Allow-Headers"]).to eq("Authorization, Content-Type")
        expect(response.headers["Access-Control-Allow-Methods"]).to eq("POST, OPTIONS")
        expect(response.headers["Vary"]).to eq("Origin")
      end
    end

    it "allows same-origin initiation without self-listing" do
      post "/api/v1/integrations/google/connect",
           headers: bearer(token).merge("Origin" => "http://www.example.com")

      expect(response).to have_http_status(:ok)
      expect(json).to have_key("url")
      expect(response.headers["Access-Control-Allow-Origin"]).to be_blank
    end
  end

  describe "OPTIONS /api/v1/integrations/google/connect" do
    it "succeeds with 204 and no bearer, issuing and consuming nothing" do
      with_env("GOOGLE_CONNECT_ORIGINS", "https://life.example.test") do
        expect {
          process :options, "/api/v1/integrations/google/connect",
                  headers: { "Origin" => "https://life.example.test" }
        }.not_to change(ConnectionToken, :count)

        expect(response).to have_http_status(:no_content)
        expect(response.body).to eq("")
        expect(session[:google_connect]).to be_blank
        expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://life.example.test")
        expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
      end
    end
  end

  describe "DELETE /api/v1/integrations/google" do
    it "revokes locally, best-effort remotes, and returns 204" do
      create(:user_integration, user: user, status: :connected, refresh_token: "refresh-to-revoke")
      stub_request(:post, Integrations::Google::DisconnectAccount::REVOKE_URL).to_return(status: 200, body: "")

      delete "/api/v1/integrations/google", headers: bearer(token)

      expect(response).to have_http_status(:no_content)
      expect(user.reload.google_integration).to be_revoked
      expect(a_request(:post, Integrations::Google::DisconnectAccount::REVOKE_URL)).to have_been_made
    end

    it "is idempotent 204 when already disconnected" do
      delete "/api/v1/integrations/google", headers: bearer(token)
      expect(response).to have_http_status(:no_content)

      delete "/api/v1/integrations/google", headers: bearer(token)
      expect(response).to have_http_status(:no_content)
    end
  end
end
