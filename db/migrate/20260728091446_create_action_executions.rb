class CreateActionExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :action_executions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :user_integration, foreign_key: true
      t.references :shortcut, foreign_key: true

      t.string :action_type, null: false
      t.integer :source, null: false
      t.integer :status, null: false, default: 0

      t.string :request_id
      t.string :external_resource_id

      t.json :input_data, null: false, default: {}
      t.json :output_data, null: false, default: {}

      t.text :display_text
      t.text :error_message

      t.integer :usage_units, null: false, default: 1
      t.integer :duration_ms

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :action_executions, :action_type
    add_index :action_executions, :source
    add_index :action_executions, :status
    add_index :action_executions, :request_id, unique: true
    add_index :action_executions, [:user_id, :created_at]
  end
end
