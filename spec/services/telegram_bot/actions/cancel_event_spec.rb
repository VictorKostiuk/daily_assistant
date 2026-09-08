require "rails_helper"

RSpec.describe TelegramBot::Actions::CancelEvent do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:bot) { instance_double(Telegram::Bot::Client, api: telegram_api) }

  it "tells the user the event is cancelled in their calendar when Google succeeds but local save fails" do
    telegram_account = create(:telegram_account)
    create(:user_integration, user: telegram_account.user)
    local_event = create(:calendar_event, user: telegram_account.user, external_event_id: "gcal_event_x", provider: "google", external_calendar_id: "primary")
    calendar = instance_double(Google::Apis::CalendarV3::CalendarService)
    allow(calendar).to receive(:delete_event)
    allow(Integrations::Google::Client).to receive(:new).and_return(instance_double(Integrations::Google::Client, calendar: calendar))
    allow_any_instance_of(CalendarEvent).to receive(:update!).and_wrap_original do |method, *args, **kwargs|
      method.receiver.title = nil
      method.call(*args, **kwargs)
    end

    pending = {
      command: "/cancel_event",
      stage: "confirmation",
      event_id: local_event.external_event_id,
      title: local_event.title,
      starts_at: local_event.starts_at,
      all_day: local_event.all_day
    }

    expect {
      described_class.call(bot: bot, update: telegram_message("yes", telegram_account), pending: pending)
    }.not_to raise_error

    expect(local_event.reload).to be_confirmed
    execution = telegram_account.user.action_executions.failed.last
    expect(execution).to be_present
    expect(execution.error_message).to include("provider_event_id=#{local_event.external_event_id}")
    expect(telegram_api).to have_received(:send_message).with(
      hash_including(text: I18n.t("telegram_bot.commands.cancel_event.local_save_failed", raise: true))
    )
    expect(telegram_api).not_to have_received(:send_message).with(
      hash_including(text: I18n.t("telegram_bot.commands.cancel_event.failed"))
    )
  end
end
