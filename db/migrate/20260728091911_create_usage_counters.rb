class CreateUsageCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_counters do |t|
      t.references :user, null: false, foreign_key: true

      t.string :metric, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false

      t.bigint :value, null: false, default: 0

      t.timestamps
    end

    add_index :usage_counters,
              [:user_id, :metric, :period_start, :period_end],
              unique: true,
              name: "index_usage_counters_on_user_metric_and_period"
  end
end
