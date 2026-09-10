class CreateStudywellAcademicTables < ActiveRecord::Migration[8.1]
  def change
    create_table :studywell_courses do |t|
      t.references :user, null: false, foreign_key: true

      t.string :name, null: false
      t.string :code
      t.string :term_label
      t.string :colour
      t.date :active_from
      t.date :active_until
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    create_table :studywell_obligations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: false, foreign_key: { to_table: :studywell_courses }

      t.integer :kind, null: false
      t.string :title, null: false
      t.datetime :due_at
      t.datetime :starts_at
      t.datetime :ends_at
      t.integer :importance
      t.integer :estimated_minutes
      t.integer :progress_percent
      t.text :notes
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end
  end
end
