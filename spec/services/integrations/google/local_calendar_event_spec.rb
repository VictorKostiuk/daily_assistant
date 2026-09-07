require "rails_helper"

RSpec.describe Integrations::Google::LocalCalendarEvent do
  let(:event) do
    Integrations::OpenRouter::EventParsing::Event.new(
      title: "Dinner with Anna", description: "Book a table", location: "Trattoria",
      starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, all_day: false
    )
  end

  describe ".sync" do
    it "creates a local calendar_event on first sync" do
      user = create(:user)

      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: event, time_zone: "Europe/Rome")

      record = CalendarEvent.find_by(user: user, provider: "google", external_event_id: "gcal_1")
      expect(record).to be_present
      expect(record.title).to eq("Dinner with Anna")
      expect(record).to be_confirmed
    end

    it "updates the same row on a second sync instead of creating a duplicate" do
      user = create(:user)
      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: event, time_zone: "Europe/Rome")

      updated_event = Integrations::OpenRouter::EventParsing::Event.new(
        title: "Dinner with Anna (moved)", description: nil, location: nil,
        starts_at: event.starts_at + 1.hour, ends_at: event.ends_at + 1.hour, all_day: false
      )
      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: updated_event, time_zone: "Europe/Rome")

      expect(CalendarEvent.where(user: user, provider: "google", external_event_id: "gcal_1").count).to eq(1)
      expect(CalendarEvent.find_by(external_event_id: "gcal_1").title).to eq("Dinner with Anna (moved)")
    end

    it "persists source metadata nested under source and reads it back flat after reload" do
      user = create(:user)
      flat = {
        "context_type" => "work",
        "source_app" => "daily-work",
        "source_entity_type" => "WorkTask",
        "source_entity_id" => "task-1"
      }

      described_class.sync(
        user: user,
        external_event_id: "gcal_1",
        external_calendar_id: "primary",
        event: event,
        time_zone: "Europe/Rome",
        metadata: flat
      )

      record = CalendarEvent.find_by!(user: user, provider: "google", external_event_id: "gcal_1")
      expect(record.metadata["source"]).to eq(flat)
      expect(SourceMetadata.load(record.metadata)).to eq(flat)
    end

    it "leaves existing metadata unchanged when metadata is omitted on a later sync" do
      user = create(:user)
      described_class.sync(
        user: user, external_event_id: "gcal_1", external_calendar_id: "primary",
        event: event, time_zone: "Europe/Rome",
        metadata: { "context_type" => "work" }
      )

      updated_event = Integrations::OpenRouter::EventParsing::Event.new(
        title: "Dinner with Anna (moved)", description: nil, location: nil,
        starts_at: event.starts_at + 1.hour, ends_at: event.ends_at + 1.hour, all_day: false
      )
      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: updated_event, time_zone: "Europe/Rome")

      record = CalendarEvent.find_by!(external_event_id: "gcal_1")
      expect(record.title).to eq("Dinner with Anna (moved)")
      expect(record.metadata["source"]).to eq("context_type" => "work")
    end

    it "rejects non-Hash metadata as Invalid, not PersistenceError" do
      user = create(:user)

      expect {
        described_class.sync(
          user: user, external_event_id: "gcal_1", external_calendar_id: "primary",
          event: event, time_zone: "Europe/Rome",
          metadata: Object.new
        )
      }.to raise_error(SourceMetadata::Invalid)
    end

    it "rejects already-nested metadata as Invalid, not PersistenceError" do
      user = create(:user)

      expect {
        described_class.sync(
          user: user, external_event_id: "gcal_1", external_calendar_id: "primary",
          event: event, time_zone: "Europe/Rome",
          metadata: { "source" => { "context_type" => "work" } }
        )
      }.to raise_error(SourceMetadata::Invalid)
    end

    it "keeps the same event id on two calendars as separate rows" do
      user = create(:user)
      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: event, time_zone: "Europe/Rome")
      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "work-cal", event: event, time_zone: "Europe/Rome")

      expect(CalendarEvent.where(user: user, provider: "google", external_event_id: "gcal_1").count).to eq(2)
      expect(CalendarEvent.find_by(external_calendar_id: "primary").external_event_id).to eq("gcal_1")
      expect(CalendarEvent.find_by(external_calendar_id: "work-cal").external_event_id).to eq("gcal_1")
    end

    it "does not attribute a nullable-calendar row to the current calendar on sync" do
      user = create(:user)
      leftover = create(:calendar_event, user: user, provider: "google", external_event_id: "gcal_1", external_calendar_id: nil)

      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: event, time_zone: "Europe/Rome")

      expect(leftover.reload.external_calendar_id).to be_nil
      expect(CalendarEvent.where(user: user, external_event_id: "gcal_1").count).to eq(2)
    end

    it "merges source fields into existing metadata and preserves unrelated keys" do
      user = create(:user)
      described_class.sync(
        user: user, external_event_id: "gcal_1", external_calendar_id: "primary",
        event: event, time_zone: "Europe/Rome",
        metadata: { "context_type" => "work", "source_app" => "daily-work" }
      )
      record = CalendarEvent.find_by!(external_event_id: "gcal_1")
      record.update!(metadata: record.metadata.merge("internal_note" => "keep-me"))

      described_class.sync(
        user: user, external_event_id: "gcal_1", external_calendar_id: "primary",
        event: event, time_zone: "Europe/Rome",
        metadata: { "source_app" => "daily-study" }
      )

      reloaded = record.reload
      expect(reloaded.metadata["internal_note"]).to eq("keep-me")
      expect(reloaded.metadata["source"]).to eq("context_type" => "work", "source_app" => "daily-study")
    end

    it "raises a distinguishable error when persistence fails after the provider write" do
      user = create(:user)
      allow(Rails.logger).to receive(:error)

      expect {
        described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: event, time_zone: nil)
      }.to raise_error(described_class::PersistenceError) { |error|
        expect(error.provider_event_id).to eq("gcal_1")
      }
      expect(Rails.logger).to have_received(:error)
    end
  end

  describe ".cancel" do
    it "marks the matching local record cancelled" do
      user = create(:user)
      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: event, time_zone: "Europe/Rome")

      described_class.cancel(user: user, external_event_id: "gcal_1", external_calendar_id: "primary")

      record = CalendarEvent.find_by(external_event_id: "gcal_1")
      expect(record).to be_cancelled
      expect(record.cancelled_at).to be_present
    end

    it "does nothing when no local record exists for that event" do
      expect { described_class.cancel(user: create(:user), external_event_id: "unknown", external_calendar_id: "primary") }.not_to raise_error
    end

    it "does not cancel a nullable-calendar row when looking up the current calendar" do
      user = create(:user)
      leftover = create(:calendar_event, user: user, provider: "google", external_event_id: "gcal_1", external_calendar_id: nil)

      described_class.cancel(user: user, external_event_id: "gcal_1", external_calendar_id: "primary")

      expect(leftover.reload).to be_confirmed
    end

    it "raises a distinguishable error when cancellation persistence fails after the provider write" do
      user = create(:user)
      described_class.sync(user: user, external_event_id: "gcal_1", external_calendar_id: "primary", event: event, time_zone: "Europe/Rome")
      record = CalendarEvent.find_by!(external_event_id: "gcal_1")
      allow(record).to receive(:update!).and_raise(ActiveRecord::RecordNotSaved.new(record))
      allow(CalendarEvent).to receive(:find_by).and_return(record)
      allow(Rails.logger).to receive(:error)

      expect {
        described_class.cancel(user: user, external_event_id: "gcal_1", external_calendar_id: "primary")
      }.to raise_error(described_class::PersistenceError) { |error|
        expect(error.provider_event_id).to eq("gcal_1")
      }
      expect(Rails.logger).to have_received(:error)
    end
  end
end
