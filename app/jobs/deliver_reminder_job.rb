class DeliverReminderJob < ApplicationJob
  queue_as :default

  def perform(reminder_id)
    reminder = Reminder.find_by(id: reminder_id)
    return if reminder.blank?

    reminder.with_lock do
      return unless reminder.pending?

      reminder.processing!
    end

    Reminders::Deliver.call(reminder: reminder)
  end
end
