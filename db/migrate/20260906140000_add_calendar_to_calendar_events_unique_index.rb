class AddCalendarToCalendarEventsUniqueIndex < ActiveRecord::Migration[8.1]
  NEW_INDEX = "index_calendar_events_on_user_provider_calendar_external_id"
  OLD_INDEX = "index_calendar_events_on_user_provider_external_id"

  def up
    remove_index :calendar_events, name: OLD_INDEX
    add_index :calendar_events,
              %i[user_id provider external_calendar_id external_event_id],
              name: NEW_INDEX,
              unique: true
  end

  def down
    collisions = connection.select_value(<<~SQL.squish)
      SELECT COUNT(*) FROM (
        SELECT 1
        FROM calendar_events
        GROUP BY user_id, provider, external_event_id
        HAVING COUNT(*) > 1
      ) AS collisions
    SQL
    if collisions.to_i.positive?
      raise ActiveRecord::IrreversibleMigration,
            "Cannot restore #{OLD_INDEX} while multiple calendars share an event id"
    end

    remove_index :calendar_events, name: NEW_INDEX
    add_index :calendar_events,
              %i[user_id provider external_event_id],
              name: OLD_INDEX,
              unique: true
  end
end
