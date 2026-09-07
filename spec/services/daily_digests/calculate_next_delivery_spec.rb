require "rails_helper"

RSpec.describe DailyDigests::CalculateNextDelivery do
  include ActiveSupport::Testing::TimeHelpers

  it "schedules later today when the delivery time has not yet passed in the digest's own zone" do
    Time.use_zone("Europe/Rome") do
      travel_to Time.zone.local(2026, 6, 15, 12, 0, 0) do
        digest = create(:daily_digest, time_zone: "Europe/Rome", delivery_time: 1.hour.from_now.strftime("%H:%M"))

        next_delivery = described_class.call(digest)

        expect(next_delivery).to be > Time.current
        expect(next_delivery.to_date).to eq(Time.zone.today)
      end
    end
  end

  it "schedules tomorrow when the delivery time has already passed today" do
    Time.use_zone("Europe/Rome") do
      travel_to Time.zone.local(2026, 6, 15, 15, 0, 0) do
        digest = create(:daily_digest, time_zone: "Europe/Rome", delivery_time: 1.hour.ago.strftime("%H:%M"))

        next_delivery = described_class.call(digest)

        expect(next_delivery.to_date).to eq(Time.zone.tomorrow)
      end
    end
  end

  it "schedules tomorrow when 1.hour.from_now crosses midnight in the digest's own zone" do
    Time.use_zone("Europe/Rome") do
      travel_to Time.zone.local(2026, 6, 15, 23, 30, 0) do
        digest = create(:daily_digest, time_zone: "Europe/Rome", delivery_time: 1.hour.from_now.strftime("%H:%M"))

        next_delivery = described_class.call(digest)

        expect(next_delivery.to_date).to eq(Time.zone.tomorrow)
        expect(next_delivery.strftime("%H:%M")).to eq("00:30")
      end
    end
  end

  it "always computes the correct local hour regardless of the globally active zone at call time" do
    digest = Time.use_zone("Europe/Rome") { create(:daily_digest, time_zone: "Europe/Rome", delivery_time: Time.zone.parse("08:00")) }

    expect(Time.zone.name).to eq("UTC")
    next_delivery = described_class.call(digest)

    expect(Time.use_zone("Europe/Rome") { next_delivery.in_time_zone("Europe/Rome").hour }).to eq(8)
  end
end
