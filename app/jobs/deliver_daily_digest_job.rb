class DeliverDailyDigestJob < ApplicationJob
  queue_as :default

  def perform(digest_id)
    digest = DailyDigest.find_by(id: digest_id)
    return if digest.blank?

    DailyDigests::Deliver.call(digest)
  rescue StandardError => error
    Rails.logger.error("[daily_digest] delivery failed for digest #{digest_id}: #{error.class}: #{error.message}")
  end
end
