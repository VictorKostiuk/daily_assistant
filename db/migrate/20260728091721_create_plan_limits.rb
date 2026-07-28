class CreatePlanLimits < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_limits do |t|
      t.references :plan, null: false, foreign_key: true

      t.string :metric, null: false
      t.integer :period, null: false
      t.bigint :limit_value, null: false

      t.timestamps
    end

    add_index :plan_limits, [:plan_id, :metric, :period], unique: true
  end
end
