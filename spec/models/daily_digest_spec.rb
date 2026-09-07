require "rails_helper"

RSpec.describe DailyDigest, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:daily_digest)).to be_valid
  end

  it "only allows one digest per user" do
    user = create(:user)
    create(:daily_digest, user: user)
    duplicate = build(:daily_digest, user: user)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to be_present
  end

  describe "#local_delivery_time" do
    # Regression test: delivery_time is a time-zone-aware :time column, so reading
    # the raw attribute outside a Time.use_zone(digest.time_zone) block returns the
    # wall-clock hour in whatever zone is globally active at read time, not the
    # digest's own zone. #local_delivery_time must always return the correct one.
    it "returns the delivery time in the digest's own time zone regardless of the ambient zone" do
      digest = nil

      Time.use_zone("Europe/Rome") do
        digest = create(:daily_digest, time_zone: "Europe/Rome", delivery_time: Time.zone.parse("08:00"))
      end

      expect(Time.zone.name).to eq("UTC")
      expect(digest.local_delivery_time.hour).to eq(8)
      expect(digest.local_delivery_time.min).to eq(0)
    end
  end

  describe ".enabled" do
    it "only returns enabled digests" do
      enabled = create(:daily_digest, enabled: true)
      create(:daily_digest, enabled: false)

      expect(DailyDigest.enabled).to contain_exactly(enabled)
    end
  end
end
