class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.references :author, null: false, foreign_key: { to_table: :users }

      t.string :title, null: false
      t.text :body, null: false

      t.integer :status, null: false, default: 0
      t.integer :audience, null: false, default: 0

      t.datetime :scheduled_at
      t.datetime :published_at

      t.timestamps
    end
  end
end
