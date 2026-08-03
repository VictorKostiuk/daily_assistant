class ScheduleDueRemindersJob < ApplicationJob
  queue_as :default

  def perform
    Reminder.pending.where(scheduled_at: ..Time.current).find_each do |reminder|
      DeliverReminderJob.perform_later(reminder.id)
    end
  end
end
