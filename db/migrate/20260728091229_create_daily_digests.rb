class CreateDailyDigests < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_digests do |t|
      t.references :user, null: false, foreign_key: true

      t.boolean :enabled, null: false, default: true

      t.time :delivery_time, null: false
      t.string :time_zone, null: false

      t.json :channels, null: false, default: ["telegram"]

      t.boolean :include_calendar_events, null: false, default: true
      t.boolean :include_tasks, null: false, default: true
      t.boolean :include_reminders, null: false, default: true
      t.boolean :include_all_day_events, null: false, default: true

      t.boolean :send_when_empty, null: false, default: false

      t.datetime :last_sent_at
      t.datetime :next_delivery_at

      t.timestamps
    end

    add_index :daily_digests, [:enabled, :next_delivery_at]
  end
end
