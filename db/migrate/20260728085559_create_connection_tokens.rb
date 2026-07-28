class CreateConnectionTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :connection_tokens do |t|
      t.references :user, null: false, foreign_key: true

      t.string :token_digest, null: false
      t.string :purpose, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :connection_tokens, :token_digest, unique: true
  end
end
