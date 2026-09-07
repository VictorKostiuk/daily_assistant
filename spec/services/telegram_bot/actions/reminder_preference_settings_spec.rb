require "rails_helper"

RSpec.describe TelegramBot::Actions::ReminderPreferenceSettings do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:bot) { instance_double(Telegram::Bot::Client, api: telegram_api) }
  let(:telegram_account) { create(:telegram_account) }

  def call_action(text)
    described_class.call(bot: bot, update: telegram_message(text, telegram_account))
  end

  it "reports the default ask-every-time status when no preference exists yet" do
    call_action("/reminder_preference")

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/asked about a reminder every time/i)))
  end

  it "switches to ask every time" do
    call_action("/reminder_preference ask")

    expect(telegram_account.user.reminder_preference.reload).to be_ask_every_time
  end

  it "switches to disabled" do
    call_action("/reminder_preference off")

    expect(telegram_account.user.reminder_preference.reload).to be_disabled_by_default
  end

  it "switches to always-apply-default with a given offset" do
    call_action("/reminder_preference always 45")

    preference = telegram_account.user.reminder_preference.reload
    expect(preference).to be_always_apply_default
    expect(preference.default_event_offset_minutes).to eq(45)
  end

  it "asks for a valid offset when 'always' has no number" do
    call_action("/reminder_preference always")

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/usage|reminder_preference/i)))
    expect(telegram_account.user.reload.reminder_preference).to be_nil
  end

  it "reports an unrecognized argument as usage help" do
    call_action("/reminder_preference whatever")

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/usage|reminder_preference/i)))
  end

  it "updates the existing preference instead of creating a duplicate" do
    create(:reminder_preference, user: telegram_account.user, event_reminder_mode: :ask_every_time)

    call_action("/reminder_preference off")

    expect(ReminderPreference.where(user: telegram_account.user).count).to eq(1)
    expect(telegram_account.user.reminder_preference.reload).to be_disabled_by_default
  end

  it "allows 0 minutes (a reminder exactly at event time), not treated as no offset" do
    call_action("/reminder_preference always 0")

    expect(telegram_account.user.reminder_preference.reload.default_event_offset_minutes).to eq(0)
  end

  it "clamps an absurdly large offset instead of raising a database range error" do
    expect {
      call_action("/reminder_preference always 999999999999999999999")
    }.not_to raise_error

    expect(telegram_account.user.reminder_preference.reload.default_event_offset_minutes).to eq(Reminder::MAX_OFFSET_MINUTES)
  end

  it "rejects a negative-looking offset instead of silently accepting its magnitude" do
    call_action("/reminder_preference always -45")

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/usage|reminder_preference/i)))
    expect(telegram_account.user.reload.reminder_preference).to be_nil
  end
end
