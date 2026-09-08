require "rails_helper"

RSpec.describe DailyDigests::Deliver do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:telegram_client) { instance_double(Telegram::Bot::Client, api: telegram_api) }

  before do
    allow(Telegram::Bot::Client).to receive(:new).and_return(telegram_client)
  end

  around do |example|
    Time.use_zone("Europe/Rome") { example.run }
  end

  it "does nothing when the digest is not yet due" do
    telegram_account = create(:telegram_account)
    digest = create(:daily_digest, user: telegram_account.user, next_delivery_at: 1.hour.from_now)

    described_class.call(digest)

    expect(telegram_api).not_to have_received(:send_message)
    expect(digest.last_sent_at).to be_nil
  end

  it "sends the digest and advances next_delivery_at when due and non-empty" do
    telegram_account = create(:telegram_account)
    user = telegram_account.user
    digest = create(:daily_digest, user: user, next_delivery_at: 1.minute.ago, delivery_time: "08:00")
    create(:calendar_event, user: user, title: "Standup", starts_at: Time.zone.now.change(hour: 9), ends_at: Time.zone.now.change(hour: 9, min: 15))

    described_class.call(digest)

    expect(telegram_api).to have_received(:send_message).with(hash_including(chat_id: telegram_account.telegram_chat_id))
    expect(digest.reload.last_sent_at).to be_present
    expect(digest.next_delivery_at).to be > Time.current
  end

  it "does not send but still advances the schedule when empty and send_when_empty is false" do
    telegram_account = create(:telegram_account)
    digest = create(:daily_digest, user: telegram_account.user, next_delivery_at: 1.minute.ago, send_when_empty: false)

    described_class.call(digest)

    expect(telegram_api).not_to have_received(:send_message)
    expect(digest.reload.last_sent_at).to be_present
    expect(digest.next_delivery_at).to be > Time.current
  end

  it "sends even when empty if send_when_empty is true" do
    telegram_account = create(:telegram_account)
    digest = create(:daily_digest, user: telegram_account.user, next_delivery_at: 1.minute.ago, send_when_empty: true)

    described_class.call(digest)

    expect(telegram_api).to have_received(:send_message)
  end
end
