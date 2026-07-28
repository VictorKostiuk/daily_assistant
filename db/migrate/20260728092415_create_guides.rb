class CreateGuides < ActiveRecord::Migration[8.1]
  def change
    create_table :guides do |t|
      t.references :author, null: false, foreign_key: { to_table: :users }

      t.string :slug, null: false
      t.string :title, null: false
      t.text :summary
      t.text :body, null: false

      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0

      t.datetime :published_at

      t.timestamps
    end

    add_index :guides, :slug, unique: true
    add_index :guides, [:status, :position]
  end
end
