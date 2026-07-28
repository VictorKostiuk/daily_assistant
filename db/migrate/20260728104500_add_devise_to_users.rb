class AddDeviseToUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :email, from: nil, to: ""
    change_column_default :users, :encrypted_password, from: nil, to: ""

    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_column :users, :remember_created_at, :datetime

    add_index :users, :reset_password_token, unique: true
  end
end
