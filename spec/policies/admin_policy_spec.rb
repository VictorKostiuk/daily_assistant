require "rails_helper"

RSpec.describe AdminPolicy do
  describe "#access?" do
    it "allows admins" do
      expect(described_class.new(build_stubbed(:user, :admin), nil).access?).to be(true)
    end

    it "denies members" do
      expect(described_class.new(build_stubbed(:user), nil).access?).to be(false)
    end

    it "denies moderators" do
      expect(described_class.new(build_stubbed(:user, :moderator), nil).access?).to be(false)
    end

    it "denies a nil user" do
      expect(described_class.new(nil, nil).access?).to be_falsey
    end
  end
end
