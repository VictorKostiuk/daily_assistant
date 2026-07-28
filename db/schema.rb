# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_28_104500) do
  create_table "action_executions", force: :cascade do |t|
    t.string "action_type", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "display_text"
    t.integer "duration_ms"
    t.text "error_message"
    t.string "external_resource_id"
    t.json "input_data", default: {}, null: false
    t.json "output_data", default: {}, null: false
    t.string "request_id"
    t.integer "shortcut_id"
    t.integer "source", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "usage_units", default: 1, null: false
    t.integer "user_id", null: false
    t.integer "user_integration_id"
    t.index ["action_type"], name: "index_action_executions_on_action_type"
    t.index ["request_id"], name: "index_action_executions_on_request_id", unique: true
    t.index ["shortcut_id"], name: "index_action_executions_on_shortcut_id"
    t.index ["source"], name: "index_action_executions_on_source"
    t.index ["status"], name: "index_action_executions_on_status"
    t.index ["user_id", "created_at"], name: "index_action_executions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_action_executions_on_user_id"
    t.index ["user_integration_id"], name: "index_action_executions_on_user_integration_id"
  end

  create_table "announcements", force: :cascade do |t|
    t.integer "audience", default: 0, null: false
    t.integer "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "published_at"
    t.datetime "scheduled_at"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_announcements_on_author_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.json "changes_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.json "metadata", default: {}, null: false
    t.integer "target_user_id"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id", "created_at"], name: "index_audit_logs_on_actor_id_and_created_at"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["target_user_id", "created_at"], name: "index_audit_logs_on_target_user_id_and_created_at"
    t.index ["target_user_id"], name: "index_audit_logs_on_target_user_id"
  end

  create_table "calendar_events", force: :cascade do |t|
    t.integer "action_execution_id"
    t.boolean "all_day", default: false, null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.string "external_calendar_id"
    t.string "external_event_id"
    t.string "location"
    t.json "metadata", default: {}, null: false
    t.string "provider", null: false
    t.datetime "starts_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "synced_at"
    t.string "time_zone", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "user_integration_id"
    t.index ["action_execution_id"], name: "index_calendar_events_on_action_execution_id"
    t.index ["user_id", "provider", "external_event_id"], name: "index_calendar_events_on_user_provider_external_id", unique: true
    t.index ["user_id", "starts_at"], name: "index_calendar_events_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_calendar_events_on_user_id"
    t.index ["user_integration_id"], name: "index_calendar_events_on_user_integration_id"
  end

  create_table "connection_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "purpose", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_connection_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_connection_tokens_on_user_id"
  end

  create_table "daily_digests", force: :cascade do |t|
    t.json "channels", default: ["telegram"], null: false
    t.datetime "created_at", null: false
    t.time "delivery_time", null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "include_all_day_events", default: true, null: false
    t.boolean "include_calendar_events", default: true, null: false
    t.boolean "include_reminders", default: true, null: false
    t.boolean "include_tasks", default: true, null: false
    t.datetime "last_sent_at"
    t.datetime "next_delivery_at"
    t.boolean "send_when_empty", default: false, null: false
    t.string "time_zone", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["enabled", "next_delivery_at"], name: "index_daily_digests_on_enabled_and_next_delivery_at"
    t.index ["user_id"], name: "index_daily_digests_on_user_id"
  end

  create_table "guides", force: :cascade do |t|
    t.integer "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.datetime "published_at"
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_guides_on_author_id"
    t.index ["slug"], name: "index_guides_on_slug", unique: true
    t.index ["status", "position"], name: "index_guides_on_status_and_position"
  end

  create_table "integration_providers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.json "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_integration_providers_on_key", unique: true
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.integer "channel", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "deliverable_id", null: false
    t.string "deliverable_type", null: false
    t.string "external_message_id"
    t.datetime "failed_at"
    t.text "failure_message"
    t.datetime "read_at"
    t.datetime "scheduled_at"
    t.datetime "sent_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["deliverable_type", "deliverable_id"], name: "index_notification_deliveries_on_deliverable"
    t.index ["status", "scheduled_at"], name: "index_notification_deliveries_on_status_and_scheduled_at"
    t.index ["user_id", "created_at"], name: "index_notification_deliveries_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_notification_deliveries_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.string "notification_type", null: false
    t.datetime "read_at"
    t.bigint "related_id"
    t.string "related_type"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["related_type", "related_id"], name: "index_notifications_on_related_type_and_related_id"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "plan_limits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "limit_value", null: false
    t.string "metric", null: false
    t.integer "period", null: false
    t.integer "plan_id", null: false
    t.datetime "updated_at", null: false
    t.index ["plan_id", "metric", "period"], name: "index_plan_limits_on_plan_id_and_metric_and_period", unique: true
    t.index ["plan_id"], name: "index_plan_limits_on_plan_id"
  end

  create_table "plan_subscriptions", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.string "external_subscription_id"
    t.string "payment_provider"
    t.integer "plan_id", null: false
    t.datetime "starts_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "trial_ends_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["external_subscription_id"], name: "index_plan_subscriptions_on_external_subscription_id"
    t.index ["plan_id"], name: "index_plan_subscriptions_on_plan_id"
    t.index ["user_id", "status"], name: "index_plan_subscriptions_on_user_id_and_status"
    t.index ["user_id"], name: "index_plan_subscriptions_on_user_id"
  end

  create_table "plans", force: :cascade do |t|
    t.integer "billing_interval"
    t.datetime "created_at", null: false
    t.string "currency", default: "UAH", null: false
    t.boolean "default", default: false, null: false
    t.text "description"
    t.json "features", default: {}, null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "price_cents"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["default"], name: "index_plans_on_default", unique: true, where: "\"default\" = TRUE"
    t.index ["key"], name: "index_plans_on_key", unique: true
  end

  create_table "reminder_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "default_event_offset_minutes"
    t.boolean "email_enabled", default: false, null: false
    t.boolean "enabled", default: true, null: false
    t.integer "event_reminder_mode", default: 0, null: false
    t.time "quiet_hours_end"
    t.time "quiet_hours_start"
    t.boolean "respect_quiet_hours", default: true, null: false
    t.boolean "telegram_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "web_enabled", default: true, null: false
    t.index ["user_id"], name: "index_reminder_preferences_on_user_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.integer "action_execution_id"
    t.datetime "cancelled_at"
    t.json "channels", default: ["telegram"], null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "failed_at"
    t.text "failure_message"
    t.json "metadata", default: {}, null: false
    t.integer "offset_minutes"
    t.integer "remindable_id"
    t.string "remindable_type"
    t.datetime "scheduled_at", null: false
    t.datetime "sent_at"
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "time_zone", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "user_integration_id"
    t.index ["action_execution_id"], name: "index_reminders_on_action_execution_id"
    t.index ["remindable_type", "remindable_id"], name: "index_reminders_on_remindable"
    t.index ["remindable_type", "remindable_id"], name: "index_reminders_on_remindable_type_and_remindable_id"
    t.index ["status", "scheduled_at"], name: "index_reminders_on_status_and_scheduled_at"
    t.index ["user_id", "scheduled_at"], name: "index_reminders_on_user_id_and_scheduled_at"
    t.index ["user_id"], name: "index_reminders_on_user_id"
    t.index ["user_integration_id"], name: "index_reminders_on_user_integration_id"
  end

  create_table "scheduled_actions", force: :cascade do |t|
    t.string "action_type", null: false
    t.boolean "active", default: true, null: false
    t.json "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "last_run_at"
    t.string "name", null: false
    t.datetime "next_run_at"
    t.string "schedule_expression", null: false
    t.integer "shortcut_id"
    t.string "time_zone", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["active", "next_run_at"], name: "index_scheduled_actions_on_active_and_next_run_at"
    t.index ["shortcut_id"], name: "index_scheduled_actions_on_shortcut_id"
    t.index ["user_id", "active"], name: "index_scheduled_actions_on_user_id_and_active"
    t.index ["user_id"], name: "index_scheduled_actions_on_user_id"
  end

  create_table "shortcuts", force: :cascade do |t|
    t.string "action_type", null: false
    t.boolean "active", default: true, null: false
    t.string "command", null: false
    t.json "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.integer "user_id", null: false
    t.index ["user_id", "active"], name: "index_shortcuts_on_user_id_and_active"
    t.index ["user_id", "command"], name: "index_shortcuts_on_user_id_and_command", unique: true
    t.index ["user_id"], name: "index_shortcuts_on_user_id"
  end

  create_table "support_conversations", force: :cascade do |t|
    t.integer "assigned_moderator_id"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.integer "priority", default: 0, null: false
    t.datetime "resolved_at"
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "subject"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["assigned_moderator_id"], name: "index_support_conversations_on_assigned_moderator_id"
    t.index ["status", "last_message_at"], name: "index_support_conversations_on_status_and_last_message_at"
    t.index ["user_id"], name: "index_support_conversations_on_user_id"
  end

  create_table "support_messages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "edited_at"
    t.boolean "internal", default: false, null: false
    t.datetime "read_at"
    t.integer "sender_id", null: false
    t.integer "source", default: 0, null: false
    t.integer "support_conversation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sender_id"], name: "index_support_messages_on_sender_id"
    t.index ["support_conversation_id", "created_at"], name: "index_support_messages_on_conversation_and_created_at"
    t.index ["support_conversation_id"], name: "index_support_messages_on_support_conversation_id"
  end

  create_table "telegram_accounts", force: :cascade do |t|
    t.boolean "bot_blocked", default: false, null: false
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.string "first_name"
    t.string "language_code"
    t.datetime "last_interaction_at"
    t.string "last_name"
    t.bigint "telegram_chat_id"
    t.bigint "telegram_user_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "username"
    t.index ["telegram_chat_id"], name: "index_telegram_accounts_on_telegram_chat_id"
    t.index ["telegram_user_id"], name: "index_telegram_accounts_on_telegram_user_id", unique: true
    t.index ["user_id"], name: "index_telegram_accounts_on_user_id"
    t.index ["username"], name: "index_telegram_accounts_on_username"
  end

  create_table "usage_counters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "metric", null: false
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.bigint "value", default: 0, null: false
    t.index ["user_id", "metric", "period_start", "period_end"], name: "index_usage_counters_on_user_metric_and_period", unique: true
    t.index ["user_id"], name: "index_usage_counters_on_user_id"
  end

  create_table "user_integrations", force: :cascade do |t|
    t.text "access_token"
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.string "external_account_email"
    t.string "external_account_id"
    t.integer "integration_provider_id", null: false
    t.datetime "last_error_at"
    t.text "last_error_message"
    t.datetime "last_used_at"
    t.json "metadata", default: {}, null: false
    t.text "refresh_token"
    t.json "scopes", default: [], null: false
    t.integer "status", default: 0, null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["integration_provider_id"], name: "index_user_integrations_on_integration_provider_id"
    t.index ["user_id", "integration_provider_id"], name: "index_user_integrations_on_user_and_provider", unique: true
    t.index ["user_id"], name: "index_user_integrations_on_user_id"
  end

  create_table "user_settings", force: :cascade do |t|
    t.boolean "announcement_notifications", default: true, null: false
    t.datetime "created_at", null: false
    t.string "date_format"
    t.string "default_calendar_id"
    t.boolean "email_notifications", default: true, null: false
    t.json "preferences", default: {}, null: false
    t.boolean "telegram_notifications", default: true, null: false
    t.string "time_format"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "week_starts_on", default: 1, null: false
    t.index ["user_id"], name: "index_user_settings_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_seen_at"
    t.string "locale", default: "en", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["status"], name: "index_users_on_status"
  end

  add_foreign_key "action_executions", "shortcuts"
  add_foreign_key "action_executions", "user_integrations"
  add_foreign_key "action_executions", "users"
  add_foreign_key "announcements", "users", column: "author_id"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "audit_logs", "users", column: "target_user_id"
  add_foreign_key "calendar_events", "action_executions"
  add_foreign_key "calendar_events", "user_integrations"
  add_foreign_key "calendar_events", "users"
  add_foreign_key "connection_tokens", "users"
  add_foreign_key "daily_digests", "users"
  add_foreign_key "guides", "users", column: "author_id"
  add_foreign_key "notification_deliveries", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "plan_limits", "plans"
  add_foreign_key "plan_subscriptions", "plans"
  add_foreign_key "plan_subscriptions", "users"
  add_foreign_key "reminder_preferences", "users"
  add_foreign_key "reminders", "action_executions"
  add_foreign_key "reminders", "user_integrations"
  add_foreign_key "reminders", "users"
  add_foreign_key "scheduled_actions", "shortcuts"
  add_foreign_key "scheduled_actions", "users"
  add_foreign_key "shortcuts", "users"
  add_foreign_key "support_conversations", "users"
  add_foreign_key "support_conversations", "users", column: "assigned_moderator_id"
  add_foreign_key "support_messages", "support_conversations"
  add_foreign_key "support_messages", "users", column: "sender_id"
  add_foreign_key "telegram_accounts", "users"
  add_foreign_key "usage_counters", "users"
  add_foreign_key "user_integrations", "integration_providers"
  add_foreign_key "user_integrations", "users"
  add_foreign_key "user_settings", "users"
end
