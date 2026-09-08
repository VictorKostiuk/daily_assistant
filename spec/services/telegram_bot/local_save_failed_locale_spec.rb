require "rails_helper"

RSpec.describe "telegram_bot local_save_failed translations" do
  it "exists in every command scope that has a failed key, and is not the failed wording" do
    commands = I18n.t("telegram_bot.commands")
    scopes_with_failed = commands.select { |_scope, entries| entries.is_a?(Hash) && entries.stringify_keys.key?("failed") }
    expect(scopes_with_failed).not_to be_empty

    scopes_with_failed.each do |scope, entries|
      entries = entries.stringify_keys
      expect(entries).to have_key("local_save_failed"), "commands.#{scope} has failed: but no local_save_failed"
      expect(entries["local_save_failed"]).to be_present
      expect(entries["local_save_failed"]).not_to eq(entries["failed"])
      expect(entries["local_save_failed"]).not_to match(/try again/i)
    end
  end
end
