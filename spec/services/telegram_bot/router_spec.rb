require "rails_helper"

RSpec.describe TelegramBot::Router do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:bot) { instance_double(Telegram::Bot::Client, api: telegram_api) }
  let(:router) { described_class.new(bot: bot, logger: Logger.new(IO::NULL)) }
  let(:telegram_account) { create(:telegram_account) }

  it "dispatches a known command to its action class" do
    router.call(telegram_message("/stop", telegram_account))

    expect(telegram_api).to have_received(:send_message).with(hash_including(chat_id: telegram_account.telegram_chat_id))
  end

  it "does nothing for an unrecognized command with no pending conversation state" do
    router.call(telegram_message("/not_a_real_command", telegram_account))

    expect(telegram_api).not_to have_received(:send_message)
  end

  it "resumes a pending conversation for a plain-text follow-up message" do
    TelegramBot::PendingAction.set(telegram_account.telegram_user_id, command: "/setup_event", stage: "description")

    router.call(telegram_message("dinner with Anna tomorrow", telegram_account))

    expect(telegram_api).to have_received(:send_message)
  end

  it "ignores a plain-text message when there is no pending conversation state" do
    router.call(telegram_message("just chatting", telegram_account))

    expect(telegram_api).not_to have_received(:send_message)
  end

  it "ignores a callback query now that no callback actions remain" do
    callback = Telegram::Bot::Types::CallbackQuery.new(
      id: "cb1", chat_instance: "abc",
      from: { id: telegram_account.telegram_user_id, is_bot: false, first_name: "Test" },
      data: "connect.local_url"
    )

    expect { router.call(callback) }.not_to raise_error
    expect(telegram_api).not_to have_received(:send_message)
  end
end
