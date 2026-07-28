class CreateShortcuts < ActiveRecord::Migration[8.1]
  def change
    create_table :shortcuts do |t|
      t.references :user, null: false, foreign_key: true

      t.string :name, null: false
      t.string :command, null: false
      t.text :description

      t.string :action_type, null: false
      t.json :configuration, null: false, default: {}

      t.boolean :active, null: false, default: true
      t.integer :usage_count, null: false, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :shortcuts, [:user_id, :command], unique: true
    add_index :shortcuts, [:user_id, :active]
  end
end
