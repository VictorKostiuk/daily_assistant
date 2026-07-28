class CreateNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_deliveries do |t|
      t.references :user, null: false, foreign_key: true

      t.string :deliverable_type, null: false
      t.bigint :deliverable_id, null: false

      t.integer :channel, null: false
      t.integer :status, null: false, default: 0

      t.text :content
      t.string :external_message_id

      t.datetime :scheduled_at
      t.datetime :sent_at
      t.datetime :read_at
      t.datetime :failed_at

      t.integer :attempts_count, null: false, default: 0
      t.text :failure_message

      t.timestamps
    end

    add_index :notification_deliveries,
              [:deliverable_type, :deliverable_id],
              name: "index_notification_deliveries_on_deliverable"

    add_index :notification_deliveries, [:status, :scheduled_at]
    add_index :notification_deliveries, [:user_id, :created_at]
  end
end
