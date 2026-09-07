require "rails_helper"

RSpec.describe DailyDigests::Generate do
  around do |example|
    Time.use_zone("Europe/Rome") { example.run }
  end

  it "reports empty when there is nothing scheduled today" do
    digest = create(:daily_digest, user: create(:user, time_zone: "Europe/Rome"))

    result = described_class.call(digest)

    expect(result.empty).to be(true)
    expect(result.text).to include("Nothing scheduled for today")
  end

  it "includes today's confirmed events and pending reminders, sorted content" do
    user = create(:user, time_zone: "Europe/Rome")
    digest = create(:daily_digest, user: user)
    create(:calendar_event, user: user, title: "Morning meeting", starts_at: Time.zone.now.change(hour: 10), ends_at: Time.zone.now.change(hour: 10, min: 30))
    create(:reminder, user: user, title: "Buy groceries", scheduled_at: Time.zone.now.change(hour: 18))
    create(:calendar_event, user: user, title: "Next week", starts_at: 1.week.from_now, ends_at: 1.week.from_now + 1.hour)

    result = described_class.call(digest)

    expect(result.empty).to be(false)
    expect(result.text).to include("Morning meeting")
    expect(result.text).to include("Buy groceries")
    expect(result.text).not_to include("Next week")
  end

  it "excludes calendar events when include_calendar_events is false" do
    user = create(:user, time_zone: "Europe/Rome")
    digest = create(:daily_digest, user: user, include_calendar_events: false)
    create(:calendar_event, user: user, title: "Morning meeting", starts_at: Time.zone.now.change(hour: 10), ends_at: Time.zone.now.change(hour: 10, min: 30))

    result = described_class.call(digest)

    expect(result.text).not_to include("Morning meeting")
  end

  it "excludes reminders when include_reminders is false" do
    user = create(:user, time_zone: "Europe/Rome")
    digest = create(:daily_digest, user: user, include_reminders: false)
    create(:reminder, user: user, title: "Buy groceries", scheduled_at: Time.zone.now.change(hour: 18))

    result = described_class.call(digest)

    expect(result.text).not_to include("Buy groceries")
  end

  it "excludes all-day events when include_all_day_events is false" do
    user = create(:user, time_zone: "Europe/Rome")
    digest = create(:daily_digest, user: user, include_all_day_events: false)
    create(:calendar_event, user: user, title: "Company retreat", all_day: true, starts_at: Time.zone.now.beginning_of_day, ends_at: Time.zone.now.end_of_day)

    result = described_class.call(digest)

    expect(result.text).not_to include("Company retreat")
  end
end
