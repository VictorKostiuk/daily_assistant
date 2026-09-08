require "rails_helper"

RSpec.describe "GET /api/v1/me", type: :request do
  def json
    JSON.parse(response.body)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def expect_unauthorized
    expect(response).to have_http_status(:unauthorized)
    expect(json).to eq(
      "error" => {
        "code" => "unauthorized",
        "message" => "Unauthorized",
        "details" => {}
      }
    )
  end

  let(:user) { create(:user) }
  let(:token) { ApiToken.issue!(user: user).first }

  it "returns exactly the permitted fields for a valid bearer token" do
    get "/api/v1/me", headers: bearer(token)

    expect(response).to have_http_status(:ok)
    expect(json).to eq(
      "id" => user.id,
      "email" => user.email,
      "first_name" => user.first_name,
      "last_name" => user.last_name,
      "time_zone" => user.time_zone,
      "locale" => user.locale,
      "role" => "member",
      "status" => "active"
    )
  end

  it "does not persist the plaintext token" do
    token
    record = ApiToken.last

    expect(record.token_digest).to eq(ApiToken.digest(token))
    expect(record.attributes.values.map(&:to_s)).not_to include(token)
    expect(record.expires_at).to be_within(1.second).of(30.days.from_now)
  end

  it "does not expose the raw token, digest, or secrets" do
    get "/api/v1/me", headers: bearer(token)

    expect(response.body).not_to include(token)
    expect(response.body).not_to include(ApiToken.digest(token))
    expect(json.keys).not_to include(
      "encrypted_password",
      "reset_password_token",
      "token_digest",
      "access_token",
      "refresh_token"
    )
  end

  it "does not log the plaintext token on issuance or an authenticated request" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    previous_logger = Rails.logger
    previous_ar_logger = ActiveRecord::Base.logger
    Rails.logger = logger
    ActiveRecord::Base.logger = logger

    begin
      issued = ApiToken.issue!(user: user).first
      get "/api/v1/me", headers: bearer(issued)
      expect(response).to have_http_status(:ok)
      expect(io.string.include?(issued)).to be(false)
    ensure
      Rails.logger = previous_logger
      ActiveRecord::Base.logger = previous_ar_logger
    end
  end

  it "returns 401 without an Authorization header" do
    get "/api/v1/me"
    expect_unauthorized
  end

  it "returns 401 for a malformed Authorization header" do
    get "/api/v1/me", headers: { "Authorization" => "Basic #{token}" }
    expect_unauthorized
  end

  it "returns 401 when the Bearer token is missing" do
    get "/api/v1/me", headers: { "Authorization" => "Bearer" }
    expect_unauthorized
  end

  it "returns 401 when the Bearer scheme is delimited by a tab" do
    get "/api/v1/me", headers: { "Authorization" => "Bearer\t#{token}" }
    expect_unauthorized
  end

  it "returns 401 for an unknown token" do
    get "/api/v1/me", headers: bearer("not-a-real-token")
    expect_unauthorized
  end

  it "returns 401 for an expired token" do
    ApiToken.find_by!(token_digest: ApiToken.digest(token)).update!(expires_at: 1.second.ago)

    get "/api/v1/me", headers: bearer(token)
    expect_unauthorized
  end

  it "returns 401 for a revoked token" do
    ApiToken.find_by!(token_digest: ApiToken.digest(token)).update!(revoked_at: Time.current)

    get "/api/v1/me", headers: bearer(token)
    expect_unauthorized
  end

  %w[suspended blocked pending].each do |status|
    it "returns 401 when the user is #{status}" do
      user.update!(status: status)

      get "/api/v1/me", headers: bearer(token)
      expect_unauthorized
    end
  end

  it "does not authenticate from a Devise session cookie without a bearer token" do
    sign_in user

    get "/api/v1/me"
    expect_unauthorized
  end

  it "rejects the next request after the user is suspended, with the same token" do
    get "/api/v1/me", headers: bearer(token)
    expect(response).to have_http_status(:ok)

    user.suspended!

    get "/api/v1/me", headers: bearer(token)
    expect_unauthorized
  end
end
