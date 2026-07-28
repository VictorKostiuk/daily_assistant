class CreateTelegramAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :telegram_accounts do |t|
      t.references :user, null: false, foreign_key: true

      t.bigint :telegram_user_id, null: false
      t.bigint :telegram_chat_id
      t.string :username
      t.string :first_name
      t.string :last_name
      t.string :language_code

      t.boolean :bot_blocked, null: false, default: false
      t.datetime :connected_at
      t.datetime :last_interaction_at

      t.timestamps
    end

    add_index :telegram_accounts, :telegram_user_id, unique: true
    add_index :telegram_accounts, :telegram_chat_id
    add_index :telegram_accounts, :username
  end
end
