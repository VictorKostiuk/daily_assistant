require "rails_helper"

RSpec.describe "API v1 StudyWell settings", type: :request do
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

  let(:user) { create(:user, time_zone: "Europe/Rome") }
  let(:token) { issue_token_for(user) }

  describe "GET /api/v1/studywell/settings" do
    it "returns the stored zone and setup false for a resolvable zone" do
      get "/api/v1/studywell/settings", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("time_zone" => "Europe/Rome", "needs_time_zone_setup" => false)
    end

    it "reports setup needed for a missing zone without writing UTC" do
      user.update_column(:time_zone, nil)

      get "/api/v1/studywell/settings", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("time_zone" => nil, "needs_time_zone_setup" => true)
      expect(user.reload.time_zone).to be_nil
    end

    it "reports setup needed for an unresolvable stored zone and returns the stored value" do
      user.update_column(:time_zone, "Not/AZone")

      get "/api/v1/studywell/settings", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("time_zone" => "Not/AZone", "needs_time_zone_setup" => true)
      expect(user.reload.time_zone).to eq("Not/AZone")
    end

    it "requires a bearer token" do
      get "/api/v1/studywell/settings"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(error_envelope(code: "unauthorized", message: "Unauthorized"))
    end
  end

  describe "PATCH /api/v1/studywell/settings" do
    it "stores a valid named zone and returns setup false" do
      user.update_column(:time_zone, nil)

      patch "/api/v1/studywell/settings",
            params: { time_zone: "America/New_York" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to eq("time_zone" => "America/New_York", "needs_time_zone_setup" => false)
      expect(user.reload.time_zone).to eq("America/New_York")
    end

    it "accepts Europe/Rome, which is not a Rails mapping key" do
      patch "/api/v1/studywell/settings",
            params: { time_zone: "Europe/Rome" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.time_zone).to eq("Europe/Rome")
    end

    it "rejects an invalid zone without persisting it" do
      patch "/api/v1/studywell/settings",
            params: { time_zone: "Not/AZone" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
      expect(json.dig("error", "details")).to eq("time_zone" => [ "is invalid" ])
      expect(user.reload.time_zone).to eq("Europe/Rome")
    end

    it "rejects resubmitting the same invalid stored zone" do
      user.update_column(:time_zone, "Not/AZone")

      patch "/api/v1/studywell/settings",
            params: { time_zone: "Not/AZone" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to eq("time_zone" => [ "is invalid" ])
      expect(user.reload.time_zone).to eq("Not/AZone")
    end

    it "rejects a non-string zone before lookup" do
      patch "/api/v1/studywell/settings",
            params: { time_zone: 1 },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to eq("time_zone" => [ "is invalid" ])
      expect(user.reload.time_zone).to eq("Europe/Rome")
    end

    it "rejects null and blank zones" do
      [ nil, "", "  " ].each do |value|
        patch "/api/v1/studywell/settings",
              params: { time_zone: value },
              headers: bearer(token), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).to include("time_zone")
        expect(user.reload.time_zone).to eq("Europe/Rome")
      end
    end

    it "returns the JSON envelope when an unrelated user attribute is invalid" do
      user.update_column(:first_name, "X")

      patch "/api/v1/studywell/settings",
            params: { time_zone: "UTC" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")
      expect(json.dig("error", "code")).to eq("validation_error")
      expect(json.dig("error", "details")).to include("first_name")
      expect(user.reload.time_zone).to eq("Europe/Rome")
      expect(user.first_name).to eq("X")
    end

    it "rejects unknown keys and an empty body" do
      patch "/api/v1/studywell/settings",
            params: { time_zone: "UTC", locale: "en" },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("locale")
      expect(user.reload.time_zone).to eq("Europe/Rome")

      patch "/api/v1/studywell/settings", params: {}, headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("base")
    end
  end

  describe "legacy-invalid accounts" do
    let(:legacy) { create(:user, password: "password123") }

    before { legacy.update_column(:time_zone, "Not/AZone") }

    it "still returns GET /api/v1/me with the stored invalid zone" do
      get "/api/v1/me", headers: bearer(issue_token_for(legacy))

      expect(response).to have_http_status(:ok)
      expect(json["time_zone"]).to eq("Not/AZone")
    end

    it "can still create a course" do
      post "/api/v1/studywell/courses",
           params: { name: "History" },
           headers: bearer(issue_token_for(legacy)), as: :json

      expect(response).to have_http_status(:created)
      expect(legacy.studywell_courses.find(json["id"]).name).to eq("History")
    end

    it "can still complete a password reset" do
      raw = legacy.send_reset_password_instructions

      put "/api/v1/auth/password", params: {
        reset_password_token: raw,
        password: "new-password-1",
        password_confirmation: "new-password-1"
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(legacy.reload.valid_password?("new-password-1")).to be(true)
      expect(legacy.time_zone).to eq("Not/AZone")
    end
  end
end
