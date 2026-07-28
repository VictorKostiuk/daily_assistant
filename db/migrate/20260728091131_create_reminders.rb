class CreateReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :remindable, polymorphic: true
      t.references :user_integration, foreign_key: true
      t.references :action_execution, foreign_key: true

      t.string :title, null: false
      t.text :description

      t.integer :offset_minutes
      t.datetime :scheduled_at, null: false
      t.string :time_zone, null: false

      t.integer :status, null: false, default: 0
      t.integer :source, null: false, default: 0

      t.json :channels, null: false, default: ["telegram"]
      t.json :metadata, null: false, default: {}

      t.datetime :sent_at
      t.datetime :cancelled_at
      t.datetime :failed_at
      t.text :failure_message

      t.timestamps
    end

    add_index :reminders, [:status, :scheduled_at]
    add_index :reminders, [:user_id, :scheduled_at]
    add_index :reminders, [:remindable_type, :remindable_id]
  end
end
