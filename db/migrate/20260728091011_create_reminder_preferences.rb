class CreateReminderPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :reminder_preferences do |t|
      t.references :user, null: false, foreign_key: true

      t.boolean :enabled, null: false, default: true

      t.boolean :telegram_enabled, null: false, default: true
      t.boolean :web_enabled, null: false, default: true
      t.boolean :email_enabled, null: false, default: false

      t.integer :default_event_offset_minutes
      t.integer :event_reminder_mode, null: false, default: 0

      t.boolean :respect_quiet_hours, null: false, default: true
      t.time :quiet_hours_start
      t.time :quiet_hours_end

      t.timestamps
    end
  end
end
