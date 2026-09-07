require "rails_helper"

RSpec.describe "API v1 reminders", type: :request do
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

  def create_params
    {
      title: "Revise chapter 3",
      scheduled_at: "2026-08-10T19:00:00+02:00",
      offset_minutes: 30,
      context_type: "study",
      source_app: "daily-study",
      source_entity_type: "StudyTask",
      source_entity_id: "8e3abc"
    }
  end

  let(:user) { create(:user, time_zone: "Europe/Rome") }
  let(:token) { issue_token_for(user) }
  let(:other) { create(:user) }

  describe "POST /api/v1/reminders" do
    it "creates a pending api reminder and returns the allowlisted shape" do
      expect {
        post "/api/v1/reminders", params: create_params, headers: bearer(token), as: :json
      }.to change { user.reminders.count }.by(1)

      reminder = user.reminders.order(:id).last
      expect(response).to have_http_status(:created)
      expect(json).to eq(
        "id" => reminder.id,
        "title" => "Revise chapter 3",
        "scheduled_at" => reminder.scheduled_at.iso8601,
        "offset_minutes" => 30,
        "time_zone" => "Europe/Rome",
        "status" => "pending",
        "source" => "api",
        "context_type" => "study",
        "source_app" => "daily-study",
        "source_entity_type" => "StudyTask",
        "source_entity_id" => "8e3abc"
      )
      expect(reminder.reload.source).to eq("api")
      expect(reminder.status).to eq("pending")
      expect(reminder.metadata["source"]).to eq(
        "context_type" => "study",
        "source_app" => "daily-study",
        "source_entity_type" => "StudyTask",
        "source_entity_id" => "8e3abc"
      )
    end

    it "stores nothing for omitted or null source fields on create" do
      post "/api/v1/reminders",
           params: { title: "No metadata", scheduled_at: "2026-08-10T19:00:00+02:00", source_app: nil },
           headers: bearer(token), as: :json

      expect(response).to have_http_status(:created)
      reminder = user.reminders.order(:id).last
      expect(reminder.reload.metadata).to eq({})
      expect(json["source_app"]).to be_nil
      expect(json["context_type"]).to be_nil
    end

    it "interprets an offset-free timestamp in the caller's time zone" do
      post "/api/v1/reminders",
           params: { title: "Local time", scheduled_at: "2026-08-10T19:00:00" },
           headers: bearer(token), as: :json

      expect(response).to have_http_status(:created)
      reminder = user.reminders.order(:id).last
      expect(reminder.reload.scheduled_at).to eq(Time.find_zone!("Europe/Rome").parse("2026-08-10 19:00"))
    end

    it "rejects a missing title with 422 before the database sees a null" do
      expect {
        post "/api/v1/reminders",
             params: { scheduled_at: "2026-08-10T19:00:00+02:00" },
             headers: bearer(token), as: :json
      }.not_to change(Reminder, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
      expect(json.dig("error", "details")).to include("title")
    end

    it "rejects an unparseable scheduled_at with 422 rather than 500" do
      expect {
        post "/api/v1/reminders",
             params: { title: "Bad time", scheduled_at: "tomorrow" },
             headers: bearer(token), as: :json
      }.not_to change(Reminder, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
    end

    it "rejects offset_minutes above MAX_OFFSET_MINUTES without clamping" do
      expect {
        post "/api/v1/reminders",
             params: { title: "Far", scheduled_at: "2026-08-10T19:00:00+02:00", offset_minutes: Reminder::MAX_OFFSET_MINUTES + 1 },
             headers: bearer(token), as: :json
      }.not_to change(Reminder, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("offset_minutes")
    end

    it "rejects unknown and ownership fields" do
      %w[user_id status source channels remindable_type remindable_id calendar_id extra].each do |field|
        expect {
          post "/api/v1/reminders",
               params: create_params.merge(field => "nope"),
               headers: bearer(token), as: :json
        }.not_to change(Reminder, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_error")
        expect(json.dig("error", "details")).to include(field)
      end
    end

    it "rejects a non-scalar source value taken from the raw body, not after permit" do
      expect {
        post "/api/v1/reminders",
             params: { title: "Typed", scheduled_at: "2026-08-10T19:00:00+02:00", source_app: [ "daily-study" ] },
             headers: bearer(token), as: :json
      }.not_to change(Reminder, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("source_app")
    end

    it "requires a bearer token" do
      post "/api/v1/reminders", params: create_params, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(error_envelope(code: "unauthorized", message: "Unauthorized"))
    end
  end

  describe "GET /api/v1/reminders" do
    it "lists only the caller's reminders in scheduled_at, id order" do
      later = create(:reminder, user: user, title: "Later", scheduled_at: Time.zone.parse("2026-08-11 10:00"))
      earlier = create(:reminder, user: user, title: "Earlier", scheduled_at: Time.zone.parse("2026-08-10 10:00"))
      same_time_newer = create(:reminder, user: user, title: "Same time newer", scheduled_at: earlier.scheduled_at)
      create(:reminder, user: other, title: "Not yours")

      get "/api/v1/reminders", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json["items"].map { |item| item["id"] }).to eq([ earlier.id, same_time_newer.id, later.id ])
      expect(json["items"].map { |item| item["title"] }).not_to include("Not yours")
      expect(json["next_page"]).to be_nil
    end

    it "pages 100 at a time and sets next_page on a truncated page" do
      freeze_time do
        101.times do |n|
          create(:reminder, user: user, title: "R#{n}", scheduled_at: n.minutes.from_now)
        end
      end

      get "/api/v1/reminders", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json["items"].size).to eq(100)
      expect(json["next_page"]).to eq(2)

      get "/api/v1/reminders", params: { page: 2 }, headers: bearer(token)

      expect(json["items"].size).to eq(1)
      expect(json["next_page"]).to be_nil
    end

    it "rejects a non-positive page" do
      get "/api/v1/reminders", params: { page: 0 }, headers: bearer(token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
    end
  end

  describe "GET /api/v1/reminders/:id" do
    it "returns the caller's reminder" do
      reminder = create(:reminder, user: user, title: "Mine")

      get "/api/v1/reminders/#{reminder.id}", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(reminder.id)
      expect(json["title"]).to eq("Mine")
    end

    it "returns 404 for another user's reminder" do
      reminder = create(:reminder, user: other)

      get "/api/v1/reminders/#{reminder.id}", headers: bearer(token)

      expect(response).to have_http_status(:not_found)
      expect(json.dig("error", "code")).to eq("not_found")
    end
  end

  describe "PATCH /api/v1/reminders/:id" do
    it "updates a pending reminder and preserves omitted source fields and unrelated metadata" do
      reminder = create(
        :reminder,
        user: user,
        title: "Old title",
        scheduled_at: Time.zone.parse("2026-08-10 19:00"),
        metadata: {
          "source" => { "context_type" => "work", "source_app" => "daily-work" },
          "internal_note" => "keep-me"
        }
      )

      patch "/api/v1/reminders/#{reminder.id}",
            params: { title: "New title", source_app: "daily-study" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      reloaded = reminder.reload
      expect(reloaded.title).to eq("New title")
      expect(reloaded.metadata["internal_note"]).to eq("keep-me")
      expect(reloaded.metadata["source"]).to eq(
        "context_type" => "work",
        "source_app" => "daily-study"
      )
      expect(json["title"]).to eq("New title")
      expect(json["context_type"]).to eq("work")
      expect(json["source_app"]).to eq("daily-study")
    end

    it "clears a source field given explicit null and leaves omitted fields" do
      reminder = create(
        :reminder,
        user: user,
        metadata: {
          "source" => { "context_type" => "work", "source_app" => "daily-work" }
        }
      )

      patch "/api/v1/reminders/#{reminder.id}",
            params: { source_app: nil },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      reloaded = reminder.reload
      expect(reloaded.metadata["source"]).to eq("context_type" => "work")
      expect(json["source_app"]).to be_nil
      expect(json["context_type"]).to eq("work")
    end

    it "rejects clearing title" do
      reminder = create(:reminder, user: user, title: "Keep")

      patch "/api/v1/reminders/#{reminder.id}",
            params: { title: nil },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(reminder.reload.title).to eq("Keep")
    end

    it "rejects an empty PATCH" do
      reminder = create(:reminder, user: user)

      patch "/api/v1/reminders/#{reminder.id}", params: {}, headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
    end

    it "returns 409 for processing, delivered, failed and cancelled reminders without changing them" do
      %i[processing delivered failed cancelled].each do |status|
        reminder = create(:reminder, user: user, status: status, title: "Frozen")

        patch "/api/v1/reminders/#{reminder.id}",
              params: { title: "Changed" },
              headers: bearer(token), as: :json

        expect(response).to have_http_status(:conflict)
        expect(json.dig("error", "code")).to eq("conflict")
        expect(reminder.reload.title).to eq("Frozen")
      end
    end

    it "returns 404 for another user's reminder" do
      reminder = create(:reminder, user: other)

      patch "/api/v1/reminders/#{reminder.id}",
            params: { title: "Hijack" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:not_found)
      expect(reminder.reload.title).not_to eq("Hijack")
    end
  end

  describe "DELETE /api/v1/reminders/:id" do
    it "cancels a pending reminder with a conditional update and returns 204" do
      reminder = create(:reminder, user: user, status: :pending)

      delete "/api/v1/reminders/#{reminder.id}", headers: bearer(token)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
      reloaded = reminder.reload
      expect(reloaded).to be_cancelled
      expect(reloaded.cancelled_at).to be_present
      expect(Reminder.exists?(reminder.id)).to be(true)
    end

    it "is idempotent for an already-cancelled reminder" do
      reminder = create(:reminder, user: user, status: :cancelled, cancelled_at: 1.hour.ago)
      original = reminder.cancelled_at

      delete "/api/v1/reminders/#{reminder.id}", headers: bearer(token)

      expect(response).to have_http_status(:no_content)
      expect(reminder.reload.cancelled_at).to eq(original)
    end

    it "returns 409 for processing, delivered and failed reminders" do
      %i[processing delivered failed].each do |status|
        reminder = create(:reminder, user: user, status: status)

        delete "/api/v1/reminders/#{reminder.id}", headers: bearer(token)

        expect(response).to have_http_status(:conflict)
        expect(json.dig("error", "code")).to eq("conflict")
        expect(reminder.reload.status).to eq(status.to_s)
      end
    end

    it "returns 404 for another user's reminder and does not cancel it" do
      reminder = create(:reminder, user: other, status: :pending)

      delete "/api/v1/reminders/#{reminder.id}", headers: bearer(token)

      expect(response).to have_http_status(:not_found)
      expect(reminder.reload).to be_pending
    end

    it "cancels with a single pending-scoped UPDATE rather than a read-then-write" do
      reminder = create(:reminder, user: user, status: :pending)
      statements = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        delete "/api/v1/reminders/#{reminder.id}", headers: bearer(token)
      end

      updates = statements.select { |sql| sql.match?(/UPDATE ["']?reminders["']?/i) }
      expect(updates.size).to eq(1)
      expect(updates.first).to include("cancelled_at")
      expect(updates.first).to match(/SET .*"status"/)
      expect(updates.first).to match(/WHERE .*"status"/)
    end
  end
end
