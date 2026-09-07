require "rails_helper"

RSpec.describe "Google browser-originated connect", type: :request do
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

  def authenticity_token_from(html)
    Nokogiri::HTML(html).at_css('input[name="authenticity_token"]')&.[]("value")
  end

  def form_action_from(html)
    Nokogiri::HTML(html).at_css("form")&.[]("action")
  end

  def query(url)
    Rack::Utils.parse_query(URI.parse(url).query)
  end

  def stub_google_oauth_network(uid: "google-sub-1", email: "ada@gmail.com")
    stub_request(:post, "https://oauth2.googleapis.com/token").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        access_token: "ya29.test-access-UNIQUE",
        refresh_token: "1//test-refresh-UNIQUE",
        expires_in: 3600,
        token_type: "Bearer"
      }.to_json
    )
    stub_request(:get, "https://www.googleapis.com/oauth2/v3/userinfo").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        sub: uid,
        email: email,
        email_verified: true,
        given_name: "Ada",
        family_name: "Lovelace"
      }.to_json
    )
    stub_request(:post, "https://www.googleapis.com/oauth2/v3/tokeninfo").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        scope: "email profile https://www.googleapis.com/auth/calendar",
        aud: ENV.fetch("GOOGLE_CLIENT_ID")
      }.to_json
    )
  end

  def initiate_connect(api_token)
    post "/api/v1/integrations/google/connect", headers: bearer(api_token)
    expect(response).to have_http_status(:ok)
    json.fetch("url")
  end

  def get_transport(url)
    get "#{URI.parse(url).path}?#{URI.parse(url).query}"
  end

  def post_request_phase(html)
    action = form_action_from(html)
    csrf = authenticity_token_from(html)
    post action, params: { authenticity_token: csrf }
  end

  def expect_not_redirected_to_google
    location = response.headers["Location"]
    expect(location.to_s).not_to include("accounts.google.com")
  end

  def expect_google_authorize_redirect
    expect(response).to have_http_status(:redirect)
    expect(response.headers["Location"]).to start_with("https://accounts.google.com/")
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  def expect_token_verifier_honors_forgery_protection(enabled)
    verifier = OmniAuth.config.request_validation_phase
    expect(verifier).to be_a(OmniAuth::RailsCsrfProtection::TokenVerifier)
    # TokenVerifier.config is ActionController::Base.config (token_verifier.rb for
    # Rails 8.1). Class-level allow_forgery_protection is what protect_against_forgery?
    # reads; calling the instance method here would delegate session to a nil request.
    expect(OmniAuth::RailsCsrfProtection::TokenVerifier.allow_forgery_protection).to eq(enabled)
    expect(ActionController::Base.allow_forgery_protection).to eq(enabled)
  end

  let(:password) { "password123" }
  let(:user) { create(:user, password: password) }
  let(:api_token) { issue_token_for(user) }

  it "does not use OmniAuth test-mode shortcuts" do
    expect(OmniAuth.config.test_mode).to be(false)
  end

  describe "transport GET" do
    it "rejects at the transport GET when a fresh browser opens a forwarded launch URL" do
      launch_url = nil
      open_session do |attacker|
        attacker.post "/api/v1/integrations/google/connect", headers: bearer(api_token)
        launch_url = JSON.parse(attacker.response.body).fetch("url")
      end

      get_transport(launch_url)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("This connection request is not valid.")
      expect(response.body).not_to include("Try again")
      expect(response.body).not_to include(query(launch_url).fetch("token"))
      expect(form_action_from(response.body)).to be_nil
      expect(user.reload.google_integration).to be_nil
    end

    it "rejects at the transport GET when a differently authenticated browser opens the launch URL" do
      victim = create(:user, password: password)
      launch_url = nil
      open_session do |attacker|
        attacker.post "/api/v1/integrations/google/connect", headers: bearer(api_token)
        launch_url = JSON.parse(attacker.response.body).fetch("url")
      end

      sign_in victim
      get_transport(launch_url)

      expect(response).to have_http_status(:forbidden)
      expect(form_action_from(response.body)).to be_nil
      expect(user.reload.google_integration).to be_nil
      expect(victim.reload.google_integration).to be_nil
    end

    it "rejects at the transport GET when the handoff has expired" do
      launch_url = initiate_connect(api_token)

      travel_to(ConnectionToken::TTL.from_now + 1.second) do
        get_transport(launch_url)
        expect(response).to have_http_status(:forbidden)
        expect(form_action_from(response.body)).to be_nil
      end
    end

    it "rejects at the transport GET when a second issue has invalidated the first handoff" do
      first_url = initiate_connect(api_token)
      second_url = initiate_connect(api_token)

      get_transport(first_url)
      expect(response).to have_http_status(:forbidden)

      get_transport(second_url)
      expect(response).to have_http_status(:ok)
      expect(form_action_from(response.body)).to include("token=")
    end

    it "does not clear a valid browser transaction on a mismatched transport GET" do
      launch_url = initiate_connect(api_token)
      handoff = query(launch_url).fetch("token")

      get "/auth/google_oauth2/connect", params: { token: "unrelated-handoff" }
      expect(response).to have_http_status(:forbidden)
      expect(session[:google_connect]["token"]).to eq(handoff)

      get_transport(launch_url)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "request-phase POST" do
    around do |example|
      with_forgery_protection { example.run }
    end

    before do
      expect_token_verifier_honors_forgery_protection(true)
    end

    it "rejects at the request-phase POST a direct POST with a valid Rails CSRF token but missing intent" do
      launch_url = nil
      open_session do |attacker|
        attacker.post "/api/v1/integrations/google/connect", headers: bearer(api_token)
        launch_url = JSON.parse(attacker.response.body).fetch("url")
      end
      handoff = query(launch_url).fetch("token")

      get new_user_session_path
      csrf = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content")
      expect(csrf).to be_present

      post "/auth/google_oauth2?token=#{CGI.escape(handoff)}", params: { authenticity_token: csrf }

      expect_not_redirected_to_google
      expect(response).to redirect_to(%r{/auth/failure})
      expect(response.headers["Location"]).not_to include(handoff)
      expect(user.reload.google_integration).to be_nil
    end

    it "rejects at the request-phase POST when the user is suspended between transport render and POST" do
      launch_url = initiate_connect(api_token)
      get_transport(launch_url)
      expect(response).to have_http_status(:ok)
      html = response.body

      user.suspended!
      post_request_phase(html)

      expect_not_redirected_to_google
      expect(response).to redirect_to(%r{/auth/failure})
      expect(user.reload.google_integration).to be_nil
    end

    it "rejects at the request-phase POST when CSRF is missing with an otherwise valid intent" do
      launch_url = initiate_connect(api_token)
      get_transport(launch_url)
      action = form_action_from(response.body)
      expect(action).to be_present

      verifier = OmniAuth.config.request_validation_phase
      unverified_env = {
        "REQUEST_METHOD" => "POST",
        "PATH_INFO" => "/auth/google_oauth2",
        "rack.input" => StringIO.new,
        "rack.session" => {}
      }
      expect { verifier.call(unverified_env) }.to raise_error(ActionController::InvalidAuthenticityToken)

      post action

      expect_not_redirected_to_google
      expect(user.reload.google_integration).to be_nil
    end

    it "rejects at the request-phase POST when CSRF is invalid with an otherwise valid intent" do
      launch_url = initiate_connect(api_token)
      get_transport(launch_url)
      action = form_action_from(response.body)

      post action, params: { authenticity_token: "invalid-csrf-token" }

      expect_not_redirected_to_google
      expect(user.reload.google_integration).to be_nil
    end
  end

  describe "callback" do
    around do |example|
      with_forgery_protection { example.run }
    end

    it "rejects at the callback an invalid OAuth state with an otherwise valid binding" do
      stub_google_oauth_network
      launch_url = initiate_connect(api_token)
      get_transport(launch_url)
      post_request_phase(response.body)
      expect_google_authorize_redirect

      get "/auth/google_oauth2/callback", params: { code: "test-code", state: "wrong-state" }

      expect(response).to redirect_to(%r{/auth/failure})
      follow_redirect!
      expect(response).to have_http_status(:forbidden)
      expect(user.reload.google_integration).to be_nil
      expect(a_request(:post, "https://oauth2.googleapis.com/token")).not_to have_been_made
    end

    it "rejects at the callback when a second issue has invalidated the original handoff" do
      stub_google_oauth_network
      launch_url = initiate_connect(api_token)
      get_transport(launch_url)
      post_request_phase(response.body)
      expect_google_authorize_redirect
      original_state = query(response.headers["Location"]).fetch("state")

      initiate_connect(api_token)

      get "/auth/google_oauth2/callback", params: { code: "test-code", state: original_state }

      expect(response).to have_http_status(:forbidden)
      expect(user.reload.google_integration).to be_nil
    end

    it "rejects at the callback a replayed handoff" do
      stub_google_oauth_network
      launch_url = initiate_connect(api_token)
      handoff = query(launch_url).fetch("token")
      get_transport(launch_url)
      post_request_phase(response.body)
      expect_google_authorize_redirect
      state = query(response.headers["Location"]).fetch("state")

      get "/auth/google_oauth2/callback", params: { code: "test-code", state: state }
      expect(response).to have_http_status(:ok)
      expect(user.reload.google_integration).to be_connected

      get "/auth/google_oauth2/callback", params: { code: "test-code", state: state }
      expect(user.reload.google_integration).to be_connected
      expect(ConnectionToken.find_by!(token_digest: ConnectionToken.digest(handoff)).used_at).to be_present
    end

    it "attaches Google on the happy path through request-phase POST and callback with no Devise session" do
      expect(OmniAuth.config.test_mode).to be(false)
      stub_google_oauth_network

      launch_url = initiate_connect(api_token)
      handoff = query(launch_url).fetch("token")

      get_transport(launch_url)
      expect(response).to have_http_status(:ok)
      action = form_action_from(response.body)
      expect(action).to include("token=")
      expect(query(action.start_with?("http") ? action : "http://www.example.com#{action}").fetch("token")).to eq(handoff)

      post_request_phase(response.body)
      expect_google_authorize_redirect
      state = query(response.headers["Location"]).fetch("state")

      get "/auth/google_oauth2/callback", params: { code: "test-code", state: state }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Google is connected. You can close this window and return to your app.")
      expect(response.body).not_to include(handoff)
      expect(request.env["warden"].user).to be_nil
      integration = user.reload.google_integration
      expect(integration).to be_connected
      expect(integration.external_account_id).to eq("google-sub-1")
      expect(session[:google_connect]).to be_blank
      expect(ConnectionToken.find_by!(token_digest: ConnectionToken.digest(handoff)).used_at).to be_present
    end

    it "attaches to the intent user on the callback, never an unrelated Devise current_user" do
      stub_google_oauth_network
      victim = create(:user, password: password)
      sign_in victim

      launch_url = initiate_connect(api_token)
      get_transport(launch_url)
      post_request_phase(response.body)
      expect_google_authorize_redirect
      state = query(response.headers["Location"]).fetch("state")

      get "/auth/google_oauth2/callback", params: { code: "test-code", state: state }

      expect(response).to have_http_status(:ok)
      expect(user.reload.google_integration).to be_connected
      expect(victim.reload.google_integration).to be_nil
    end

    it "returns 500 on the callback when attach persistence fails after the claim" do
      stub_google_oauth_network
      launch_url = initiate_connect(api_token)
      handoff = query(launch_url).fetch("token")
      get_transport(launch_url)
      post_request_phase(response.body)
      expect_google_authorize_redirect
      state = query(response.headers["Location"]).fetch("state")

      allow(Integrations::Google::ConnectAccount).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(UserIntegration.new))

      get "/auth/google_oauth2/callback", params: { code: "test-code", state: state }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("Return to the originating app and start a new connection")
      expect(session[:google_connect]).to be_blank
      expect(ConnectionToken.find_by!(token_digest: ConnectionToken.digest(handoff)).used_at).to be_present
      expect(user.reload.google_integration).to be_nil
    end
  end

  describe "provider decline and failure" do
    around do |example|
      with_forgery_protection { example.run }
    end

    it "does not put the handoff in the failure Location when the transport Referer carried it" do
      launch_url = initiate_connect(api_token)
      handoff = query(launch_url).fetch("token")
      get_transport(launch_url)
      html = response.body
      referer = "http://www.example.com#{URI.parse(launch_url).request_uri}"

      post form_action_from(html),
           params: { authenticity_token: authenticity_token_from(html) },
           headers: { "HTTP_REFERER" => referer }
      expect_google_authorize_redirect
      state = query(response.headers["Location"]).fetch("state")

      get "/auth/google_oauth2/callback", params: { error: "access_denied", state: state }

      expect(response).to redirect_to(%r{/auth/failure})
      location = response.headers["Location"]
      expect(location).not_to include(handoff)
      expect(Rack::Utils.parse_query(URI(location).query)).not_to have_key("origin")
    end

    it "leaves the transaction unspent on provider decline before claim and allows same-browser retry" do
      launch_url = initiate_connect(api_token)
      handoff = query(launch_url).fetch("token")
      get_transport(launch_url)
      post_request_phase(response.body)
      expect_google_authorize_redirect
      state = query(response.headers["Location"]).fetch("state")

      get "/auth/google_oauth2/callback", params: { error: "access_denied", state: state }
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Try again")
      expect(ConnectionToken.find_by!(token_digest: ConnectionToken.digest(handoff)).used_at).to be_nil
      expect(session[:google_connect]["token"]).to eq(handoff)

      retry_href = Nokogiri::HTML(response.body).at_css("a")&.[]("href")
      get retry_href
      expect(response).to have_http_status(:ok)
      post_request_phase(response.body)
      expect_google_authorize_redirect
    end

    it "renders failure with no Devise session as 403 when the binding is missing" do
      get "/auth/failure", params: { message: "access_denied", strategy: "google_oauth2" }

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("Try again")
      expect(request.env["warden"].user).to be_nil
    end
  end
end
