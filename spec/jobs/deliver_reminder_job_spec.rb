require "rails_helper"

RSpec.describe DeliverReminderJob do
  it "delivers a pending reminder" do
    reminder = create(:reminder, status: :pending)
    expect(Reminders::Deliver).to receive(:call).with(reminder: reminder)

    described_class.new.perform(reminder.id)
  end

  it "does nothing for a reminder that is no longer pending (prevents double delivery)" do
    reminder = create(:reminder, status: :processing)
    expect(Reminders::Deliver).not_to receive(:call)

    described_class.new.perform(reminder.id)

    expect(reminder.reload).to be_processing
  end

  it "does nothing for a reminder id that no longer exists" do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end

  it "moves the reminder to processing before handing off to Deliver" do
    reminder = create(:reminder, status: :pending)

    allow(Reminders::Deliver).to receive(:call) do |reminder:|
      expect(reminder).to be_processing
    end

    described_class.new.perform(reminder.id)
  end
end
