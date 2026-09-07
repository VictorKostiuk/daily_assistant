require "rails_helper"

RSpec.describe "API v1 calendar events", type: :request do
  def json
    JSON.parse(response.body)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def issue_token_for(user)
    ApiToken.issue!(user: user).first
  end

  def serialize_google(payload)
    JSON.parse(
      Google::Apis::CalendarV3::Event::Representation
        .new(payload).to_json(user_options: { skip_undefined: true })
    )
  end

  def timed_google_event(id: "gcal_1", summary: "Dinner with Anna", description: "Book a table", location: "Trattoria")
    Google::Apis::CalendarV3::Event.new(
      id: id,
      summary: summary,
      description: description,
      location: location,
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: Time.iso8601("2026-08-10T19:00:00+02:00"),
        time_zone: "Europe/Rome"
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: Time.iso8601("2026-08-10T20:00:00+02:00"),
        time_zone: "Europe/Rome"
      )
    )
  end

  def all_day_google_event(id: "gcal_all", summary: "Conference", start_date: "2026-08-10", exclusive_end: "2026-08-13")
    Google::Apis::CalendarV3::Event.new(
      id: id,
      summary: summary,
      start: Google::Apis::CalendarV3::EventDateTime.new(date: start_date),
      end: Google::Apis::CalendarV3::EventDateTime.new(date: exclusive_end)
    )
  end

  def stub_google_client
    calendar = instance_double(Google::Apis::CalendarV3::CalendarService)
    client = instance_double(Integrations::Google::Client, calendar: calendar)
    allow(Integrations::Google::Client).to receive(:new).and_return(client)
    [ client, calendar ]
  end

  # SELECTs against calendar_events issued while the block runs. SCHEMA queries
  # are excluded because they are connection setup, not per-request work.
  def count_calendar_event_selects
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:name] == "SCHEMA"

      count += 1 if payload[:sql].to_s.match?(/\ASELECT\b.*\bcalendar_events\b/im)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  def provider_error(status_code, message)
    Google::Apis::ClientError.new(
      message,
      status_code: status_code,
      body: { "error" => { "message" => message } }.to_json
    )
  end

  let(:user) { create(:user, time_zone: "Europe/Rome") }
  let(:token) { issue_token_for(user) }
  let(:other) { create(:user) }

  let(:create_params) do
    {
      title: "Dinner with Anna",
      description: "Book a table",
      location: "Trattoria",
      starts_at: "2026-08-10T19:00:00+02:00",
      ends_at: "2026-08-10T20:00:00+02:00",
      all_day: false,
      context_type: "work",
      source_app: "daily-work"
    }
  end

  describe "POST /api/v1/calendar/events" do
    it "creates an event, syncs from the provider response, and returns the flat shape" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:insert_event).and_return(timed_google_event)

      post "/api/v1/calendar/events", params: create_params, headers: bearer(token), as: :json

      expect(response).to have_http_status(:created)
      expect(json["id"]).to eq("gcal_1")
      expect(json["title"]).to eq("Dinner with Anna")
      expect(json["description"]).to eq("Book a table")
      expect(json["location"]).to eq("Trattoria")
      expect(json["all_day"]).to be(false)
      expect(json["time_zone"]).to eq("Europe/Rome")
      expect(json["context_type"]).to eq("work")
      expect(json["source_app"]).to eq("daily-work")
      expect(json).not_to have_key("kind")
      expect(json).not_to have_key("etag")

      record = CalendarEvent.find_by!(user: user, provider: "google", external_event_id: "gcal_1")
      expect(record.reload.title).to eq("Dinner with Anna")
      expect(record.external_calendar_id).to eq("primary")
      expect(record.metadata["source"]).to eq("context_type" => "work", "source_app" => "daily-work")
    end

    it "does not construct the Google client for invalid input" do
      create(:user_integration, user: user)
      expect(Integrations::Google::Client).not_to receive(:new)

      post "/api/v1/calendar/events",
           params: { title: "Missing times" },
           headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
    end

    it "returns 409 when Google is not connected without constructing the client" do
      expect(Integrations::Google::Client).not_to receive(:new)

      post "/api/v1/calendar/events", params: create_params, headers: bearer(token), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "code")).to eq("integration_not_connected")
    end

    it "rejects ownership fields" do
      create(:user_integration, user: user)
      expect(Integrations::Google::Client).not_to receive(:new)

      post "/api/v1/calendar/events",
           params: create_params.merge(calendar_id: "other", user_id: other.id),
           headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details").keys).to include("calendar_id", "user_id")
    end

    it "maps provider 403 to provider_error rather than not_found" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:insert_event).and_raise(provider_error(403, "rateLimitExceeded"))

      expect {
        post "/api/v1/calendar/events", params: create_params, headers: bearer(token), as: :json
      }.not_to change(CalendarEvent, :count)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("rateLimitExceeded")
    end

    it "maps provider 404 to provider_error rather than not_found" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:insert_event).and_raise(provider_error(404, "Not Found"))

      expect {
        post "/api/v1/calendar/events", params: create_params, headers: bearer(token), as: :json
      }.not_to change(CalendarEvent, :count)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("Not Found")
    end

    it "returns 502 local_save_failed when the provider write succeeds and local save fails" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      unsyncable = Google::Apis::CalendarV3::Event.new(id: "gcal_1")
      allow(calendar).to receive(:insert_event).and_return(unsyncable)

      post "/api/v1/calendar/events", params: create_params, headers: bearer(token), as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("local_save_failed")
      expect(json.dig("error", "details", "provider_event_id")).to eq("gcal_1")
      expect(json.dig("error", "message")).not_to include("SQLite")
      expect(json.dig("error", "message")).not_to match(/not null/i)
    end
  end

  describe "PATCH /api/v1/calendar/events/:id" do
    it "sends a sparse patch body that omits unspecified fields" do
      create(:user_integration, user: user)
      create(
        :calendar_event,
        user: user,
        external_event_id: "gcal_1",
        external_calendar_id: "primary",
        metadata: { "source" => { "context_type" => "work" }, "internal_note" => "keep-me" }
      )
      _client, calendar = stub_google_client
      captured = nil
      allow(calendar).to receive(:patch_event) do |_cal, _id, event_object|
        captured = event_object
        timed_google_event(summary: "Renamed")
      end
      allow(calendar).to receive(:update_event).and_raise("must not PUT")

      patch "/api/v1/calendar/events/gcal_1",
            params: { title: "Renamed" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      body = serialize_google(captured)
      expect(body).to eq("summary" => "Renamed")
      expect(body).not_to have_key("description")
      expect(body).not_to have_key("location")
      expect(json["title"]).to eq("Renamed")

      record = CalendarEvent.find_by!(external_event_id: "gcal_1")
      expect(record.reload.title).to eq("Renamed")
      expect(record.metadata["internal_note"]).to eq("keep-me")
      expect(record.metadata["source"]).to eq("context_type" => "work")
    end

    it "serializes explicit null description so it can clear without wiping location" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      captured = nil
      allow(calendar).to receive(:patch_event) do |_cal, _id, event_object|
        captured = event_object
        timed_google_event(description: nil)
      end

      patch "/api/v1/calendar/events/gcal_1",
            params: { description: nil },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      body = serialize_google(captured)
      expect(body).to have_key("description")
      expect(body["description"]).to be_nil
      expect(body).not_to have_key("location")
    end

    it "fetches and annotates locally for a metadata-only PATCH with zero mutations" do
      create(:user_integration, user: user)
      create(
        :calendar_event,
        user: user,
        external_event_id: "gcal_1",
        external_calendar_id: "primary",
        title: "Dinner with Anna",
        metadata: { "source" => { "context_type" => "work" }, "internal_note" => "keep-me" }
      )
      _client, calendar = stub_google_client
      expect(calendar).to receive(:get_event).with("primary", "gcal_1").and_return(timed_google_event)
      expect(calendar).not_to receive(:patch_event)
      expect(calendar).not_to receive(:update_event)
      expect(calendar).not_to receive(:insert_event)
      expect(calendar).not_to receive(:delete_event)

      patch "/api/v1/calendar/events/gcal_1",
            params: { source_app: "daily-study" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      record = CalendarEvent.find_by!(external_event_id: "gcal_1")
      expect(record.reload.metadata["internal_note"]).to eq("keep-me")
      expect(record.metadata["source"]).to eq("context_type" => "work", "source_app" => "daily-study")
      expect(json["source_app"]).to eq("daily-study")
      expect(json["context_type"]).to eq("work")
    end

    it "maps a metadata-only provider 403 to provider_error without mutating the local row" do
      create(:user_integration, user: user)
      seeded_metadata = {
        "source" => { "context_type" => "work", "source_app" => "daily-work" },
        "internal_note" => "keep-me"
      }
      record = create(
        :calendar_event,
        user: user,
        external_event_id: "gcal_1",
        external_calendar_id: "primary",
        metadata: seeded_metadata
      )
      snapshot = record.reload.attributes
      count_before = CalendarEvent.count
      _client, calendar = stub_google_client
      expect(calendar).to receive(:get_event).and_raise(provider_error(403, "rateLimitExceeded"))
      expect(calendar).not_to receive(:patch_event)
      expect(calendar).not_to receive(:update_event)
      expect(calendar).not_to receive(:insert_event)
      expect(calendar).not_to receive(:delete_event)

      patch "/api/v1/calendar/events/gcal_1",
            params: { source_app: "daily-study" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("rateLimitExceeded")
      expect(CalendarEvent.count).to eq(count_before)
      expect(record.reload.attributes).to eq(snapshot)
    end

    it "maps a metadata-only provider 404 to not_found without mutating the local row" do
      create(:user_integration, user: user)
      seeded_metadata = {
        "source" => { "context_type" => "work", "source_app" => "daily-work" },
        "internal_note" => "keep-me"
      }
      record = create(
        :calendar_event,
        user: user,
        external_event_id: "gcal_1",
        external_calendar_id: "primary",
        metadata: seeded_metadata
      )
      snapshot = record.reload.attributes
      count_before = CalendarEvent.count
      _client, calendar = stub_google_client
      expect(calendar).to receive(:get_event).and_raise(provider_error(404, "Not Found"))
      expect(calendar).not_to receive(:patch_event)
      expect(calendar).not_to receive(:update_event)
      expect(calendar).not_to receive(:insert_event)
      expect(calendar).not_to receive(:delete_event)

      patch "/api/v1/calendar/events/gcal_1",
            params: { source_app: "daily-study" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:not_found)
      expect(json.dig("error", "code")).to eq("not_found")
      expect(json.dig("error", "message")).not_to include("Not Found")
      expect(CalendarEvent.count).to eq(count_before)
      expect(record.reload.attributes).to eq(snapshot)
    end

    it "returns 500 internal_error, not local_save_failed, when a metadata-only local save fails" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:get_event).and_return(Google::Apis::CalendarV3::Event.new(id: "gcal_1"))

      patch "/api/v1/calendar/events/gcal_1",
            params: { source_app: "daily-study" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(json.dig("error", "code")).to eq("internal_error")
      expect(json.dig("error", "code")).not_to eq("local_save_failed")
    end

    it "does not construct the client for an empty PATCH" do
      create(:user_integration, user: user)
      expect(Integrations::Google::Client).not_to receive(:new)

      patch "/api/v1/calendar/events/gcal_1", params: {}, headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires starts_at, ends_at and all_day together" do
      create(:user_integration, user: user)
      expect(Integrations::Google::Client).not_to receive(:new)

      patch "/api/v1/calendar/events/gcal_1",
            params: { starts_at: "2026-08-10T19:00:00+02:00" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details").keys).to include("ends_at", "all_day")
    end

    it "syncs all-day ends_at from the exclusive provider date without drift across repeated patches" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:patch_event).and_return(
        all_day_google_event,
        all_day_google_event
      )

      2.times do
        patch "/api/v1/calendar/events/gcal_all",
              params: {
                starts_at: "2026-08-10",
                ends_at: "2026-08-12",
                all_day: true
              },
              headers: bearer(token), as: :json
        expect(response).to have_http_status(:ok)
      end

      record = CalendarEvent.find_by!(external_event_id: "gcal_all")
      expect(record.reload.ends_at.in_time_zone("Europe/Rome").to_date).to eq(Date.new(2026, 8, 12))
      expect(json["ends_at"]).to eq("2026-08-12")
      expect(json["starts_at"]).to eq("2026-08-10")
      expect(json["all_day"]).to be(true)
    end

    it "maps provider 404 on the event id to not_found" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:patch_event).and_raise(provider_error(404, "Not Found"))

      patch "/api/v1/calendar/events/missing",
            params: { title: "Renamed" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:not_found)
      expect(json.dig("error", "code")).to eq("not_found")
      expect(json.dig("error", "message")).not_to include("Not Found")
    end

    it "maps provider 403 to provider_error rather than not_found" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:patch_event).and_raise(provider_error(403, "rateLimitExceeded"))

      patch "/api/v1/calendar/events/gcal_1",
            params: { title: "Renamed" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("rateLimitExceeded")
    end
  end

  describe "DELETE /api/v1/calendar/events/:id" do
    it "deletes at Google and cancels the matching local row for the current calendar" do
      create(:user_integration, user: user)
      matching = create(:calendar_event, user: user, external_event_id: "gcal_1", external_calendar_id: "primary")
      other_cal = create(:calendar_event, user: user, external_event_id: "gcal_1", external_calendar_id: "work-cal", title: "Other calendar")
      _client, calendar = stub_google_client
      expect(calendar).to receive(:delete_event).with("primary", "gcal_1")

      delete "/api/v1/calendar/events/gcal_1", headers: bearer(token)

      expect(response).to have_http_status(:no_content)
      expect(matching.reload).to be_cancelled
      expect(other_cal.reload).to be_confirmed
    end

    it "returns 204 when Google deletes and no local row matches the current calendar" do
      create(:user_integration, user: user)
      leftover = create(:calendar_event, user: user, external_event_id: "gcal_1", external_calendar_id: nil)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:delete_event)

      delete "/api/v1/calendar/events/gcal_1", headers: bearer(token)

      expect(response).to have_http_status(:no_content)
      expect(leftover.reload).to be_confirmed
    end

    it "maps provider 404 on the event id to not_found" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:delete_event).and_raise(provider_error(404, "Not Found"))

      delete "/api/v1/calendar/events/missing", headers: bearer(token)

      expect(response).to have_http_status(:not_found)
      expect(json.dig("error", "code")).to eq("not_found")
      expect(json.dig("error", "message")).not_to include("Not Found")
    end

    it "maps provider 403 to provider_error and does not cancel the local row" do
      create(:user_integration, user: user)
      matching = create(:calendar_event, user: user, external_event_id: "gcal_1", external_calendar_id: "primary")
      _client, calendar = stub_google_client
      allow(calendar).to receive(:delete_event).and_raise(provider_error(403, "rateLimitExceeded"))
      expect(Integrations::Google::LocalCalendarEvent).not_to receive(:cancel)

      delete "/api/v1/calendar/events/gcal_1", headers: bearer(token)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("rateLimitExceeded")
      expect(matching.reload).to be_confirmed
    end
  end

  describe "GET /api/v1/calendar/events" do
    it "requires offset-bearing from and to and passes them through as RFC3339 bounds" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      listed = Google::Apis::CalendarV3::Events.new(
        items: [ timed_google_event ],
        next_page_token: nil
      )
      expect(calendar).to receive(:list_events).with(
        "primary",
        hash_including(
          single_events: true,
          order_by: "startTime",
          time_min: "2026-08-10T00:00:00+02:00",
          time_max: "2026-08-11T00:00:00+02:00",
          max_results: 100
        )
      ).and_return(listed)

      get "/api/v1/calendar/events",
          params: { from: "2026-08-10T00:00:00+02:00", to: "2026-08-11T00:00:00+02:00" },
          headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json["items"].size).to eq(1)
      expect(json["items"].first["id"]).to eq("gcal_1")
      expect(json["items"].first["title"]).to eq("Dinner with Anna")
      expect(json["next_page_token"]).to be_nil
    end

    it "rejects a bare timestamp bound with 422 and does not construct the client" do
      create(:user_integration, user: user)
      expect(Integrations::Google::Client).not_to receive(:new)

      get "/api/v1/calendar/events",
          params: { from: "2026-08-10T00:00:00", to: "2026-08-11T00:00:00+02:00" },
          headers: bearer(token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
    end

    it "passes Google's next_page_token through and repeats the same bounds on the token request" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      first = Google::Apis::CalendarV3::Events.new(items: [ timed_google_event ], next_page_token: "CigKtoken")
      second = Google::Apis::CalendarV3::Events.new(items: [], next_page_token: nil)
      allow(calendar).to receive(:list_events).and_return(first, second)

      get "/api/v1/calendar/events",
          params: { from: "2026-08-10T00:00:00+02:00", to: "2026-08-11T00:00:00+02:00" },
          headers: bearer(token)
      expect(json["next_page_token"]).to eq("CigKtoken")

      get "/api/v1/calendar/events",
          params: {
            from: "2026-08-10T00:00:00+02:00",
            to: "2026-08-11T00:00:00+02:00",
            page_token: "CigKtoken"
          },
          headers: bearer(token)

      expect(calendar).to have_received(:list_events).with(
        "primary",
        hash_including(
          time_min: "2026-08-10T00:00:00+02:00",
          time_max: "2026-08-11T00:00:00+02:00",
          page_token: "CigKtoken"
        )
      )
      expect(json["next_page_token"]).to be_nil
    end

    it "maps a Google invalid page token 400 to 422" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:list_events).and_raise(
        Google::Apis::ClientError.new(
          "Invalid page token",
          status_code: 400,
          body: { "error" => { "message" => "Invalid page token" } }.to_json
        )
      )

      get "/api/v1/calendar/events",
          params: {
            from: "2026-08-10T00:00:00+02:00",
            to: "2026-08-11T00:00:00+02:00",
            page_token: "stale"
          },
          headers: bearer(token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
    end

    it "maps provider 403 to provider_error rather than not_found" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:list_events).and_raise(provider_error(403, "rateLimitExceeded"))

      get "/api/v1/calendar/events",
          params: { from: "2026-08-10T00:00:00+02:00", to: "2026-08-11T00:00:00+02:00" },
          headers: bearer(token)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("rateLimitExceeded")
    end

    it "maps provider 404 to provider_error rather than not_found" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:list_events).and_raise(provider_error(404, "Not Found"))

      get "/api/v1/calendar/events",
          params: { from: "2026-08-10T00:00:00+02:00", to: "2026-08-11T00:00:00+02:00" },
          headers: bearer(token)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("Not Found")
    end

    it "does not map an unidentified provider 400 to validation_error" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client
      allow(calendar).to receive(:list_events).and_raise(
        Google::Apis::ClientError.new(
          "badRequest",
          status_code: 400,
          body: { "error" => { "message" => "badRequest" } }.to_json
        )
      )

      get "/api/v1/calendar/events",
          params: { from: "2026-08-10T00:00:00+02:00", to: "2026-08-11T00:00:00+02:00" },
          headers: bearer(token)

      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(json.dig("error", "message")).not_to include("badRequest")
    end

    # OFFSET_TIME accepts shapes Time.iso8601 still rejects. Un-rescued, these
    # left time_range as a bare ArgumentError, which BaseController does not
    # handle — so a documented 422 arrived as a 500.
    #
    # "2026-02-30" is deliberately absent: Time.iso8601 parses it and rolls it
    # to 2026-03-02, so it is not one of these cases.
    {
      "an impossible month in from" =>
        { from: "2026-99-01T00:00:00Z", to: "2027-01-01T00:00:00Z", fields: %w[from] },
      "an impossible month in to" =>
        { from: "2026-01-01T00:00:00Z", to: "2027-99-01T00:00:00Z", fields: %w[to] },
      "an impossible hour in from" =>
        { from: "2026-01-01T25:00:00Z", to: "2027-01-01T00:00:00Z", fields: %w[from] },
      "impossible values in both bounds" =>
        { from: "2026-99-01T00:00:00Z", to: "2027-99-01T00:00:00Z", fields: %w[from to] }
    }.each do |label, cse|
      it "returns 422 naming the offending bound for #{label}" do
        create(:user_integration, user: user)
        expect(Integrations::Google::Client).not_to receive(:new)

        get "/api/v1/calendar/events",
            params: { from: cse[:from], to: cse[:to] },
            headers: bearer(token)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_error")
        expect(json.dig("error", "details").keys).to match_array(cse[:fields])
        cse[:fields].each { |field| expect(json.dig("error", "details", field)).to eq([ "is invalid" ]) }
      end
    end

    # A raw "+" in a query string decodes to a space, which the regex already
    # rejects. Percent-encoding is what lets an out-of-range offset reach
    # Time.iso8601 at all, so this case is not a duplicate of the ones above.
    it "returns 422 for a percent-encoded out-of-range UTC offset" do
      create(:user_integration, user: user)
      expect(Integrations::Google::Client).not_to receive(:new)

      get "/api/v1/calendar/events?from=2026-01-01T00:00:00%2B99:00&to=2027-01-01T00:00:00Z",
          headers: bearer(token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
      expect(json.dig("error", "details", "from")).to eq([ "is invalid" ])
    end

    it "rejects an impossible bound before any provider access, leaving the stored tokens untouched" do
      # Connected on purpose: an unconnected user would be refused by
      # google_ready? anyway, which would prove nothing about ordering.
      integration = create(:user_integration, user: user)
      before_attrs = integration.attributes.slice(
        "access_token", "refresh_token", "token_expires_at", "status", "updated_at"
      )
      expect(Integrations::Google::Client).not_to receive(:new)
      expect(Integrations::Google::ListEvents).not_to receive(:call)

      get "/api/v1/calendar/events",
          params: { from: "2026-99-01T00:00:00Z", to: "2027-01-01T00:00:00Z" },
          headers: bearer(token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(integration.reload.attributes.slice(*before_attrs.keys)).to eq(before_attrs)
    end

    it "annotates each event from its own local row and leaks nothing across rows" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client

      create(:calendar_event, user: user, provider: "google", external_calendar_id: "primary",
             external_event_id: "gcal_a",
             metadata: { "source" => { "context_type" => "work", "source_app" => "daily-work" } })
      create(:calendar_event, user: user, provider: "google", external_calendar_id: "primary",
             external_event_id: "gcal_b",
             metadata: { "source" => { "context_type" => "study", "source_entity_id" => "b-7" } })
      # Same provider event id, different calendar — must not be picked up.
      create(:calendar_event, user: user, provider: "google", external_calendar_id: "archive@group.calendar.google.com",
             external_event_id: "gcal_c",
             metadata: { "source" => { "context_type" => "life", "source_app" => "WRONG-CALENDAR" } })
      # Same provider event id, different user — must not be picked up.
      create(:calendar_event, user: other, provider: "google", external_calendar_id: "primary",
             external_event_id: "gcal_d",
             metadata: { "source" => { "context_type" => "global", "source_app" => "WRONG-USER" } })

      ids = %w[gcal_a gcal_b gcal_c gcal_d gcal_e]
      allow(calendar).to receive(:list_events).and_return(
        Google::Apis::CalendarV3::Events.new(
          items: ids.map { |id| timed_google_event(id: id) }, next_page_token: nil
        )
      )

      get "/api/v1/calendar/events",
          params: { from: "2026-08-10T00:00:00+02:00", to: "2026-08-11T00:00:00+02:00" },
          headers: bearer(token)

      expect(response).to have_http_status(:ok)
      items = json["items"].index_by { |item| item["id"] }
      expect(items.keys).to match_array(ids)

      expect(items["gcal_a"]["context_type"]).to eq("work")
      expect(items["gcal_a"]["source_app"]).to eq("daily-work")
      expect(items["gcal_b"]["context_type"]).to eq("study")
      expect(items["gcal_b"]["source_entity_id"]).to eq("b-7")
      expect(items["gcal_b"]["source_app"]).to be_nil

      # other calendar, other user, and never annotated at all
      %w[gcal_c gcal_d gcal_e].each do |id|
        expect(items[id]["context_type"]).to be_nil
        expect(items[id]["source_app"]).to be_nil
        expect(items[id]["source_entity_type"]).to be_nil
        expect(items[id]["source_entity_id"]).to be_nil
      end

      # The response shape does not change with annotation: all four source
      # keys are present on every item, null when unset.
      json["items"].each do |item|
        expect(item.keys).to include("context_type", "source_app", "source_entity_type", "source_entity_id")
      end
    end

    it "keeps the calendar_events SELECT count bounded as the page size grows" do
      create(:user_integration, user: user)
      _client, calendar = stub_google_client

      measured = [ 1, 5, 25, 100 ].to_h do |size|
        allow(calendar).to receive(:list_events).and_return(
          Google::Apis::CalendarV3::Events.new(
            items: Array.new(size) { |i| timed_google_event(id: "gcal_#{i}") }, next_page_token: nil
          )
        )

        count = count_calendar_event_selects do
          get "/api/v1/calendar/events",
              params: { from: "2026-08-10T00:00:00+02:00", to: "2026-08-11T00:00:00+02:00" },
              headers: bearer(token)
        end

        expect(response).to have_http_status(:ok)
        expect(json["items"].size).to eq(size)
        [ size, count ]
      end

      # One batched lookup per request, whatever the page size. Before this was
      # batched the count tracked the number of events returned.
      expect(measured).to eq(1 => 1, 5 => 1, 25 => 1, 100 => 1)
    end
  end
end
