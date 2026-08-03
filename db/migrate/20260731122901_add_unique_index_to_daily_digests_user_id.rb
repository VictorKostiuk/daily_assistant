class AddUniqueIndexToDailyDigestsUserId < ActiveRecord::Migration[8.1]
  def change
    remove_index :daily_digests, :user_id, name: "index_daily_digests_on_user_id"
    add_index :daily_digests, :user_id, name: "index_daily_digests_on_user_id", unique: true
  end
end
