require "rails_helper"

RSpec.describe Reminders::Create do
  it "creates a pending reminder with the user's time zone" do
    user = create(:user, time_zone: "Europe/Rome")

    reminder = described_class.call(user: user, title: "Buy groceries", scheduled_at: 1.hour.from_now)

    expect(reminder).to be_persisted
    expect(reminder).to be_pending
    expect(reminder.title).to eq("Buy groceries")
    expect(reminder.time_zone).to eq("Europe/Rome")
    expect(reminder.source).to eq("telegram")
  end

  it "falls back to the app's default zone when the user has none set" do
    user = create(:user, time_zone: nil)

    reminder = described_class.call(user: user, title: "Buy groceries", scheduled_at: 1.hour.from_now)

    expect(reminder.time_zone).to eq(Time.zone.name)
  end

  it "attaches an event-relative reminder to its remindable and offset" do
    calendar_event = create(:calendar_event)

    reminder = described_class.call(
      user: calendar_event.user,
      title: calendar_event.title,
      scheduled_at: calendar_event.starts_at - 30.minutes,
      remindable: calendar_event,
      offset_minutes: 30
    )

    expect(reminder.remindable).to eq(calendar_event)
    expect(reminder.offset_minutes).to eq(30)
  end

  it "records an API-created reminder as source api, not telegram" do
    user = create(:user)

    reminder = described_class.call(
      user: user,
      title: "Revise chapter 3",
      scheduled_at: 1.hour.from_now,
      source: :api
    )

    expect(reminder.reload.source).to eq("api")
  end

  it "persists source metadata nested under source and reads it back flat after reload" do
    user = create(:user)
    flat = {
      "context_type" => "study",
      "source_app" => "daily-study",
      "source_entity_type" => "StudyTask",
      "source_entity_id" => "8e3abc"
    }

    reminder = described_class.call(
      user: user,
      title: "Revise chapter 3",
      scheduled_at: 1.hour.from_now,
      source: :api,
      metadata: flat
    )

    reloaded = reminder.reload
    expect(reloaded.metadata["source"]).to eq(flat)
    expect(SourceMetadata.load(reloaded.metadata)).to eq(flat)
  end

  it "persists partial metadata and allows omitting it entirely" do
    user = create(:user)

    omitted = described_class.call(user: user, title: "No metadata", scheduled_at: 1.hour.from_now)
    expect(omitted.reload.metadata).to eq({})

    partial = described_class.call(
      user: user,
      title: "Partial metadata",
      scheduled_at: 1.hour.from_now,
      metadata: { "source_app" => "daily-study" }
    )
    expect(partial.reload.metadata["source"]).to eq("source_app" => "daily-study")
    expect(SourceMetadata.load(partial.reload.metadata)).to eq("source_app" => "daily-study")
  end

  it "does not set remindable from source metadata" do
    user = create(:user)

    reminder = described_class.call(
      user: user,
      title: "Revise chapter 3",
      scheduled_at: 1.hour.from_now,
      metadata: {
        "source_entity_type" => "StudyTask",
        "source_entity_id" => "8e3abc"
      }
    )

    reloaded = reminder.reload
    expect(reloaded.remindable_type).to be_nil
    expect(reloaded.remindable_id).to be_nil
    expect(reloaded.metadata["source"]).to eq(
      "source_entity_type" => "StudyTask",
      "source_entity_id" => "8e3abc"
    )
  end

  it "rejects non-Hash metadata as Invalid" do
    user = create(:user)

    expect {
      described_class.call(
        user: user,
        title: "Bad metadata",
        scheduled_at: 1.hour.from_now,
        metadata: Object.new
      )
    }.to raise_error(SourceMetadata::Invalid)
  end

  it "rejects already-nested metadata instead of storing it unreadably" do
    user = create(:user)

    expect {
      described_class.call(
        user: user,
        title: "Nested",
        scheduled_at: 1.hour.from_now,
        metadata: { "source" => { "context_type" => "study" } }
      )
    }.to raise_error(SourceMetadata::Invalid)
  end
end
