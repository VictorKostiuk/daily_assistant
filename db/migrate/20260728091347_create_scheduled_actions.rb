class CreateScheduledActions < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_actions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :shortcut, foreign_key: true

      t.string :name, null: false
      t.string :action_type, null: false
      t.json :configuration, null: false, default: {}

      t.string :time_zone, null: false
      t.string :schedule_expression, null: false

      t.boolean :active, null: false, default: true
      t.datetime :next_run_at
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :scheduled_actions, [:active, :next_run_at]
    add_index :scheduled_actions, [:user_id, :active]
  end
end
