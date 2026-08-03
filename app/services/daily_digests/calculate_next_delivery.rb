module DailyDigests
  class CalculateNextDelivery
    def self.call(digest)
      new(digest).call
    end

    def initialize(digest)
      @digest = digest
    end

    def call
      local_time = digest.local_delivery_time

      Time.use_zone(time_zone) do
        candidate = Time.zone.now.change(hour: local_time.hour, min: local_time.min, sec: 0)
        candidate += 1.day if candidate <= Time.zone.now
        candidate
      end
    end

    private

    attr_reader :digest

    def time_zone
      digest.time_zone.presence || Time.zone.name
    end
  end
end
