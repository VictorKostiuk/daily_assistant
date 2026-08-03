class ScheduleDueDailyDigestsJob < ApplicationJob
  queue_as :default

  def perform
    DailyDigest.enabled.where(next_delivery_at: ..Time.current).find_each do |digest|
      DeliverDailyDigestJob.perform_later(digest.id)
    end
  end
end
