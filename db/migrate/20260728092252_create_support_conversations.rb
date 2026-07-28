class CreateSupportConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :support_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :assigned_moderator,
                  foreign_key: { to_table: :users }

      t.string :subject
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 0
      t.integer :source, null: false, default: 0

      t.datetime :last_message_at
      t.datetime :resolved_at
      t.datetime :closed_at

      t.timestamps
    end

    add_index :support_conversations, [:status, :last_message_at]
  end
end
