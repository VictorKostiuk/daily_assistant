class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :encrypted_password, null: false

      t.integer :role, null: false, default: 0
      t.integer :status, null: false, default: 0

      t.string :first_name
      t.string :last_name
      t.string :time_zone
      t.string :locale, null: false, default: "en"

      t.datetime :last_seen_at
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :role
    add_index :users, :status
  end
end
