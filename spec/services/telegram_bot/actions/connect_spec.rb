require "rails_helper"

RSpec.describe TelegramBot::Actions::Connect do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:bot) { instance_double(Telegram::Bot::Client, api: telegram_api) }
  let(:telegram_account) { create(:telegram_account) }

  it "replies with a plain message and no inline keyboard" do
    described_class.call(bot: bot, update: telegram_message("/connect", telegram_account))

    expect(telegram_api).to have_received(:send_message).with(
      hash_including(
        chat_id: telegram_account.telegram_chat_id,
        text: a_string_matching(/integration controls in your Daily Assistant client/i)
      )
    )
    expect(telegram_api).not_to have_received(:send_message).with(hash_including(reply_markup: anything))
  end
end
