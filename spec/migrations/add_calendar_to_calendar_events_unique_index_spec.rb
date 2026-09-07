require "rails_helper"
require Rails.root.join("db/migrate/20260906140000_add_calendar_to_calendar_events_unique_index")

RSpec.describe "AddCalendarToCalendarEventsUniqueIndex" do
  def with_temporary_database
    previous = ActiveRecord::Base.connection_db_config
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    yield ActiveRecord::Base.connection
  ensure
    ActiveRecord::Base.establish_connection(previous)
  end

  def create_old_schema(connection)
    connection.create_table :calendar_events do |t|
      t.integer :user_id, null: false
      t.string :provider, null: false
      t.string :external_event_id
      t.string :external_calendar_id
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.string :time_zone, null: false
      t.boolean :all_day, null: false, default: false
      t.integer :status, null: false, default: 0
      t.json :metadata, null: false, default: {}
    end
    connection.add_index :calendar_events,
                         %i[user_id provider external_event_id],
                         unique: true,
                         name: "index_calendar_events_on_user_provider_external_id"
  end

  def insert_row(connection, user_id:, calendar:, event_id:)
    quoted_calendar = calendar.nil? ? "NULL" : connection.quote(calendar)
    connection.execute(<<~SQL.squish)
      INSERT INTO calendar_events (user_id, provider, external_event_id, external_calendar_id, title, starts_at, time_zone, all_day, status, metadata)
      VALUES (#{user_id}, 'google', #{connection.quote(event_id)}, #{quoted_calendar}, 'Event', '2026-08-10 10:00:00', 'Europe/Rome', 0, 0, '{}')
    SQL
  end

  def migration
    AddCalendarToCalendarEventsUniqueIndex.new
  end

  it "widens uniqueness, preserves nullable-calendar rows, and allows the same event on two calendars" do
    with_temporary_database do |connection|
      create_old_schema(connection)
      insert_row(connection, user_id: 1, calendar: "primary", event_id: "evt-1")
      insert_row(connection, user_id: 1, calendar: nil, event_id: "evt-legacy")

      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }

      expect {
        insert_row(connection, user_id: 1, calendar: "work-cal", event_id: "evt-1")
      }.not_to raise_error

      rows = connection.select_all("SELECT external_calendar_id, external_event_id FROM calendar_events").to_a
      expect(rows).to include(
        hash_including("external_event_id" => "evt-legacy", "external_calendar_id" => nil)
      )
      expect(rows.count { |row| row["external_event_id"] == "evt-1" }).to eq(2)

      expect {
        ActiveRecord::Migration.suppress_messages { migration.migrate(:down) }
      }.to raise_error(ActiveRecord::IrreversibleMigration, /multiple calendars share an event id/)

      indexes = connection.indexes("calendar_events").map(&:name)
      expect(indexes).to include("index_calendar_events_on_user_provider_calendar_external_id")
      expect(indexes).not_to include("index_calendar_events_on_user_provider_external_id")
    end
  end

  it "restores the three-column index when no collision exists" do
    with_temporary_database do |connection|
      create_old_schema(connection)
      insert_row(connection, user_id: 1, calendar: "primary", event_id: "evt-1")
      insert_row(connection, user_id: 1, calendar: nil, event_id: "evt-legacy")

      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
      ActiveRecord::Migration.suppress_messages { migration.migrate(:down) }

      indexes = connection.indexes("calendar_events").map(&:name)
      expect(indexes).to include("index_calendar_events_on_user_provider_external_id")
      expect(indexes).not_to include("index_calendar_events_on_user_provider_calendar_external_id")
    end
  end
end
