class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :actor, foreign_key: { to_table: :users }

      t.string :action, null: false
      t.string :auditable_type
      t.bigint :auditable_id

      t.references :target_user, foreign_key: { to_table: :users }

      t.json :changes_data, null: false, default: {}
      t.json :metadata, null: false, default: {}

      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :audit_logs, [:auditable_type, :auditable_id]
    add_index :audit_logs, [:actor_id, :created_at]
    add_index :audit_logs, [:target_user_id, :created_at]
    add_index :audit_logs, :action
  end
end
