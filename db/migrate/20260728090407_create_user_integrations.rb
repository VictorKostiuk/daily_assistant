class CreateUserIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :user_integrations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :integration_provider, null: false, foreign_key: true

      t.integer :status, null: false, default: 0

      t.text :access_token
      t.text :refresh_token
      t.datetime :token_expires_at

      t.string :external_account_id
      t.string :external_account_email

      t.json :scopes, null: false, default: []
      t.json :metadata, null: false, default: {}

      t.datetime :connected_at
      t.datetime :last_used_at
      t.datetime :last_error_at
      t.text :last_error_message

      t.timestamps
    end

    add_index :user_integrations,
              [:user_id, :integration_provider_id],
              unique: true,
              name: "index_user_integrations_on_user_and_provider"
  end
end
