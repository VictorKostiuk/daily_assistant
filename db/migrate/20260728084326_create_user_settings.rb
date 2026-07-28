class CreateUserSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :user_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.boolean :telegram_notifications, null: false, default: true
      t.boolean :email_notifications, null: false, default: true
      t.boolean :announcement_notifications, null: false, default: true

      t.string :default_calendar_id
      t.integer :week_starts_on, null: false, default: 1
      t.string :date_format
      t.string :time_format

      t.json :preferences, null: false, default: {}

      t.timestamps
    end
  end
end
