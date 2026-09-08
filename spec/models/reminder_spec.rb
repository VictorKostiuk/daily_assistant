require "rails_helper"

RSpec.describe Reminder, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:reminder)).to be_valid
  end

  it "can be attached to a remindable calendar event" do
    calendar_event = create(:calendar_event)
    reminder = create(:reminder, remindable: calendar_event)

    expect(reminder.remindable).to eq(calendar_event)
  end

  it "defaults to pending status and telegram channel" do
    reminder = create(:reminder)

    expect(reminder).to be_pending
    expect(reminder.channels).to eq([ "telegram" ])
  end

  describe ".pending" do
    it "only returns pending reminders" do
      pending = create(:reminder, status: :pending)
      create(:reminder, status: :delivered)
      create(:reminder, status: :cancelled)

      expect(Reminder.pending).to contain_exactly(pending)
    end
  end

  it "keeps existing source integers stable and appends api" do
    expect(described_class.sources).to eq(
      "web" => 0,
      "telegram" => 1,
      "calendar_sync" => 2,
      "system" => 3,
      "api" => 4
    )
  end
end
