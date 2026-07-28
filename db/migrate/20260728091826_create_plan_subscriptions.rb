class CreatePlanSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :plan_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true

      t.integer :status, null: false, default: 0

      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.datetime :trial_ends_at
      t.datetime :cancelled_at

      t.string :payment_provider
      t.string :external_subscription_id

      t.timestamps
    end

    add_index :plan_subscriptions, [:user_id, :status]
    add_index :plan_subscriptions, :external_subscription_id
  end
end
