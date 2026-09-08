require "rails_helper"

RSpec.describe Reminders::Deliver do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:telegram_client) { instance_double(Telegram::Bot::Client, api: telegram_api) }

  before do
    allow(Telegram::Bot::Client).to receive(:new).and_return(telegram_client)
  end

  it "sends the reminder text to the user's linked chat and marks it delivered" do
    telegram_account = create(:telegram_account)
    reminder = create(:reminder, user: telegram_account.user, title: "Submit the report")

    described_class.call(reminder: reminder)

    expect(telegram_api).to have_received(:send_message).with(
      chat_id: telegram_account.telegram_chat_id,
      text: "Reminder: Submit the report"
    )
    expect(reminder.reload).to be_delivered
    expect(reminder.sent_at).to be_present
  end

  it "marks the reminder failed when the user has no linked Telegram account" do
    reminder = create(:reminder)

    described_class.call(reminder: reminder)

    expect(telegram_api).not_to have_received(:send_message)
    expect(reminder.reload).to be_failed
    expect(reminder.failure_message).to be_present
  end

  it "does not send when telegram is not among the reminder's channels" do
    telegram_account = create(:telegram_account)
    reminder = create(:reminder, user: telegram_account.user, channels: [ "web" ])

    described_class.call(reminder: reminder)

    expect(telegram_api).not_to have_received(:send_message)
    expect(reminder.reload).to be_failed
  end
end
