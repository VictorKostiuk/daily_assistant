require "rails_helper"

RSpec.describe Integrations::Google::EventPayload do
  def serialize(payload)
    JSON.parse(
      Google::Apis::CalendarV3::Event::Representation
        .new(payload).to_json(user_options: { skip_undefined: true })
    )
  end

  def timed_event(**overrides)
    Integrations::OpenRouter::EventParsing::Event.new(
      {
        title: "Dinner with Anna",
        description: "Book a table",
        location: "Trattoria",
        starts_at: Time.zone.parse("2026-08-10 19:00"),
        ends_at: Time.zone.parse("2026-08-10 20:00"),
        all_day: false
      }.merge(overrides)
    )
  end

  def all_day_event
    Integrations::OpenRouter::EventParsing::Event.new(
      title: "Conference",
      description: nil,
      location: nil,
      starts_at: Time.zone.parse("2026-08-10"),
      ends_at: Time.zone.parse("2026-08-12"),
      all_day: true
    )
  end

  describe ".build" do
    it "still serializes all five Core fields for a full Telegram-style payload" do
      body = serialize(described_class.build(timed_event, time_zone: "Europe/Rome"))

      expect(body.keys).to include("summary", "description", "location", "start", "end")
      expect(body["summary"]).to eq("Dinner with Anna")
      expect(body["description"]).to eq("Book a table")
      expect(body["location"]).to eq("Trattoria")
    end

    it "omits unspecified fields from the serialized sparse body rather than sending null" do
      payload = described_class.build(
        { "title" => "Renamed" },
        time_zone: "Europe/Rome",
        only: [ "title" ]
      )
      body = serialize(payload)

      expect(body).to eq("summary" => "Renamed")
      expect(body).not_to have_key("description")
      expect(body).not_to have_key("location")
      expect(body).not_to have_key("start")
      expect(body).not_to have_key("end")
    end

    it "serializes an explicit null description so PATCH can clear it" do
      payload = described_class.build(
        { "description" => nil },
        time_zone: "Europe/Rome",
        only: [ "description" ]
      )
      body = serialize(payload)

      expect(body).to have_key("description")
      expect(body["description"]).to be_nil
      expect(body).not_to have_key("summary")
    end

    it "writes the all-day exclusive end as start date + 1" do
      body = serialize(described_class.build(all_day_event, time_zone: "Europe/Rome"))

      expect(body.dig("start", "date")).to eq("2026-08-10")
      expect(body.dig("end", "date")).to eq("2026-08-13")
      expect(body["start"]).not_to have_key("dateTime")
      expect(body["end"]).not_to have_key("dateTime")
    end

    it "serializes the alternate start/end representation as null on a sparse timed-to-all-day payload" do
      payload = described_class.build(
        {
          "starts_at" => Time.zone.parse("2026-08-10"),
          "ends_at" => Time.zone.parse("2026-08-10"),
          "all_day" => true
        },
        time_zone: "Europe/Rome",
        only: [ "starts_at", "ends_at", "all_day" ]
      )
      body = serialize(payload)

      expect(body["start"]).to include("date" => "2026-08-10")
      expect(body["start"]).to have_key("dateTime")
      expect(body["start"]["dateTime"]).to be_nil
      expect(body["end"]).to include("date" => "2026-08-11")
      expect(body["end"]).to have_key("dateTime")
      expect(body["end"]["dateTime"]).to be_nil
    end

    it "serializes the alternate start/end representation as null on a sparse all-day-to-timed payload" do
      payload = described_class.build(
        {
          "starts_at" => Time.zone.parse("2026-08-10 19:00"),
          "ends_at" => Time.zone.parse("2026-08-10 20:00"),
          "all_day" => false
        },
        time_zone: "Europe/Rome",
        only: [ "starts_at", "ends_at", "all_day" ]
      )
      body = serialize(payload)

      expect(body["start"]).to have_key("date")
      expect(body["start"]["date"]).to be_nil
      expect(body["start"]).to have_key("dateTime")
      expect(body["end"]).to have_key("date")
      expect(body["end"]["date"]).to be_nil
    end
  end

  describe ".from_provider" do
    it "reads a timed Google event into Core's inclusive shape" do
      google_event = Google::Apis::CalendarV3::Event.new(
        summary: "Dinner with Anna",
        description: "Book a table",
        location: "Trattoria",
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: Time.iso8601("2026-08-10T19:00:00+02:00"),
          time_zone: "Europe/Rome"
        ),
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: Time.iso8601("2026-08-10T20:00:00+02:00"),
          time_zone: "Europe/Rome"
        )
      )

      event = described_class.from_provider(google_event, time_zone: "Europe/Rome")

      expect(event.title).to eq("Dinner with Anna")
      expect(event.description).to eq("Book a table")
      expect(event.location).to eq("Trattoria")
      expect(event.all_day).to be(false)
      expect(event.starts_at).to eq(Time.find_zone!("Europe/Rome").parse("2026-08-10 19:00"))
      expect(event.ends_at).to eq(Time.find_zone!("Europe/Rome").parse("2026-08-10 20:00"))
    end

    it "applies the inverse exclusive-end conversion so all-day ends_at does not drift" do
      google_event = Google::Apis::CalendarV3::Event.new(
        summary: "Conference",
        start: Google::Apis::CalendarV3::EventDateTime.new(date: "2026-08-10"),
        end: Google::Apis::CalendarV3::EventDateTime.new(date: "2026-08-13")
      )

      event = described_class.from_provider(google_event, time_zone: "Europe/Rome")

      expect(event.all_day).to be(true)
      expect(event.starts_at.to_date).to eq(Date.new(2026, 8, 10))
      expect(event.ends_at.to_date).to eq(Date.new(2026, 8, 12))
    end

    it "round-trips an all-day event twice without shifting ends_at" do
      original = all_day_event
      first_payload = described_class.build(original, time_zone: "Europe/Rome")
      first_body = serialize(first_payload)
      first_read = described_class.from_provider(
        Google::Apis::CalendarV3::Event.new(
          summary: first_body["summary"],
          start: Google::Apis::CalendarV3::EventDateTime.new(date: first_body.dig("start", "date")),
          end: Google::Apis::CalendarV3::EventDateTime.new(date: first_body.dig("end", "date"))
        ),
        time_zone: "Europe/Rome"
      )

      second_payload = described_class.build(first_read, time_zone: "Europe/Rome")
      second_body = serialize(second_payload)
      second_read = described_class.from_provider(
        Google::Apis::CalendarV3::Event.new(
          summary: second_body["summary"],
          start: Google::Apis::CalendarV3::EventDateTime.new(date: second_body.dig("start", "date")),
          end: Google::Apis::CalendarV3::EventDateTime.new(date: second_body.dig("end", "date"))
        ),
        time_zone: "Europe/Rome"
      )

      expect(first_body.dig("end", "date")).to eq("2026-08-13")
      expect(second_body.dig("end", "date")).to eq("2026-08-13")
      expect(first_read.ends_at.to_date).to eq(Date.new(2026, 8, 12))
      expect(second_read.ends_at.to_date).to eq(Date.new(2026, 8, 12))
    end
  end
end
