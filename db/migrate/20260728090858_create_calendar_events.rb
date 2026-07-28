class CreateCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :user_integration, foreign_key: true
      t.references :action_execution, foreign_key: true

      t.string :provider, null: false
      t.string :external_event_id
      t.string :external_calendar_id

      t.string :title, null: false
      t.text :description
      t.string :location

      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string :time_zone, null: false

      t.boolean :all_day, null: false, default: false
      t.integer :status, null: false, default: 0

      t.json :metadata, null: false, default: {}

      t.datetime :synced_at
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :calendar_events,
              [:user_id, :provider, :external_event_id],
              unique: true,
              name: "index_calendar_events_on_user_provider_external_id"

    add_index :calendar_events, [:user_id, :starts_at]
  end
end
