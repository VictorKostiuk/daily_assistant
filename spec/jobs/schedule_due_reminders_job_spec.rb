require "rails_helper"

RSpec.describe ScheduleDueRemindersJob do
  it "enqueues delivery only for reminders that are due and still pending" do
    due = create(:reminder, status: :pending, scheduled_at: 1.minute.ago)
    create(:reminder, status: :pending, scheduled_at: 1.hour.from_now)
    create(:reminder, status: :delivered, scheduled_at: 1.minute.ago)

    expect { described_class.new.perform }.to have_enqueued_job(DeliverReminderJob).with(due.id).exactly(1).times
  end
end
