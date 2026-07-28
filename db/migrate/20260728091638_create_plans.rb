class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description

      t.integer :status, null: false, default: 0
      t.boolean :default, null: false, default: false

      t.integer :price_cents
      t.string :currency, null: false, default: "UAH"
      t.integer :billing_interval

      t.json :features, null: false, default: {}

      t.timestamps
    end

    add_index :plans, :key, unique: true
    add_index :plans, :default, unique: true, where: '"default" = TRUE'
  end
end
