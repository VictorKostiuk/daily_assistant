class CreateIntegrationProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :integration_providers do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description

      t.boolean :active, null: false, default: true
      t.json :configuration, null: false, default: {}

      t.timestamps
    end

    add_index :integration_providers, :key, unique: true
  end
end
