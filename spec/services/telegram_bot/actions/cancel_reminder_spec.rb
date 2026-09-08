require "rails_helper"

RSpec.describe TelegramBot::Actions::CancelReminder do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:bot) { instance_double(Telegram::Bot::Client, api: telegram_api) }
  let(:telegram_account) { create(:telegram_account) }

  def call_action(text, pending: nil)
    described_class.call(bot: bot, update: telegram_message(text, telegram_account), pending: pending)
  end

  it "asks which reminder to cancel on the bare command" do
    call_action("/cancel_reminder")

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/which reminder/i)))
  end

  it "reports there is nothing to cancel when the user has no pending reminders" do
    call_action("cancel the report reminder")

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/no upcoming reminders/i)))
  end

  context "with a pending reminder" do
    let!(:reminder) { create(:reminder, user: telegram_account.user, title: "Submit the report") }

    it "proposes a confirmation once the AI matches a reminder" do
      allow(Integrations::OpenRouter::MatchReminder).to receive(:call).and_return(reminder.id.to_s)

      call_action("cancel the report reminder")

      expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/Submit the report/)))
      expect(reminder.reload).to be_pending
    end

    it "reports no match when the AI can't find one" do
      allow(Integrations::OpenRouter::MatchReminder).to receive(:call).and_return(nil)

      call_action("cancel my flight reminder")

      expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/could not tell which reminder/i)))
    end

    it "cancels the reminder once the user confirms with yes" do
      pending = { command: "/cancel_reminder", stage: "confirmation", reminder_id: reminder.id, title: reminder.title }

      call_action("yes", pending: pending)

      expect(reminder.reload).to be_cancelled
      expect(reminder.cancelled_at).to be_present
      expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/cancelled/i)))
    end

    it "leaves the reminder untouched when the user declines" do
      pending = { command: "/cancel_reminder", stage: "confirmation", reminder_id: reminder.id, title: reminder.title }

      call_action("no thanks", pending: pending)

      expect(reminder.reload).to be_pending
      expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/did not cancel/i)))
    end

    it "does not cancel a reminder that belongs to a different user even with a guessed id" do
      other_reminder = create(:reminder, title: "Someone else's reminder")
      pending = { command: "/cancel_reminder", stage: "confirmation", reminder_id: other_reminder.id, title: other_reminder.title }

      call_action("yes", pending: pending)

      expect(other_reminder.reload).to be_pending
    end
  end
end
