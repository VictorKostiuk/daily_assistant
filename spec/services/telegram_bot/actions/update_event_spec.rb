require "rails_helper"

RSpec.describe TelegramBot::Actions::UpdateEvent do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:bot) { instance_double(Telegram::Bot::Client, api: telegram_api) }

  it "tells the user the change is in their calendar when Google succeeds but local save fails" do
    telegram_account = create(:telegram_account)
    create(:user_integration, user: telegram_account.user)
    google_event = Google::Apis::CalendarV3::Event.new(id: "gcal_event_x", html_link: "https://calendar.google.com/x")
    calendar = instance_double(Google::Apis::CalendarV3::CalendarService)
    allow(calendar).to receive(:update_event).and_return(google_event)
    allow(Integrations::Google::Client).to receive(:new).and_return(instance_double(Integrations::Google::Client, calendar: calendar))

    pending = {
      command: "/update_event",
      stage: "confirmation",
      event_id: google_event.id,
      event: {
        title: nil,
        description: nil,
        location: nil,
        starts_at: Time.zone.parse("2026-08-10 20:00"),
        ends_at: Time.zone.parse("2026-08-10 21:00"),
        all_day: false
      }
    }

    expect {
      described_class.call(bot: bot, update: telegram_message("yes", telegram_account), pending: pending)
    }.not_to raise_error

    expect(CalendarEvent.where(external_event_id: google_event.id)).to be_empty
    execution = telegram_account.user.action_executions.failed.last
    expect(execution).to be_present
    expect(execution.error_message).to include("provider_event_id=#{google_event.id}")
    expect(telegram_api).to have_received(:send_message).with(
      hash_including(text: I18n.t("telegram_bot.commands.update_event.local_save_failed", raise: true))
    )
    expect(telegram_api).not_to have_received(:send_message).with(
      hash_including(text: I18n.t("telegram_bot.commands.update_event.failed"))
    )
  end
end
