class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true

      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :body

      t.string :related_type
      t.bigint :related_id

      t.datetime :read_at
      t.datetime :dismissed_at

      t.timestamps
    end

    add_index :notifications, [:user_id, :read_at]
    add_index :notifications, [:related_type, :related_id]
  end
end
