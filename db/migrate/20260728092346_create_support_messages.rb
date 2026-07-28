class CreateSupportMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :support_messages do |t|
      t.references :support_conversation, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }

      t.text :body, null: false
      t.integer :source, null: false, default: 0

      t.boolean :internal, null: false, default: false
      t.datetime :read_at
      t.datetime :edited_at

      t.timestamps
    end

    add_index :support_messages,
              [:support_conversation_id, :created_at],
              name: "index_support_messages_on_conversation_and_created_at"
  end
end
