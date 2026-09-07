module TelegramMessageHelper
  def telegram_message(text, telegram_account)
    Telegram::Bot::Types::Message.new(
      message_id: 1,
      date: Time.now.to_i,
      chat: { id: telegram_account.telegram_chat_id, type: "private" },
      from: { id: telegram_account.telegram_user_id, is_bot: false, first_name: "Test" },
      text: text,
      entities: text.start_with?("/") ? [ { type: "bot_command", offset: 0, length: (text.index(" ") || text.length) } ] : []
    )
  end
end

RSpec.configure do |config|
  config.include TelegramMessageHelper
end
