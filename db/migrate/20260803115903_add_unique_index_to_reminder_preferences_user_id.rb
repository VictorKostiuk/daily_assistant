class AddUniqueIndexToReminderPreferencesUserId < ActiveRecord::Migration[8.1]
  def change
    remove_index :reminder_preferences, :user_id, name: "index_reminder_preferences_on_user_id"
    add_index :reminder_preferences, :user_id, name: "index_reminder_preferences_on_user_id", unique: true
  end
end
