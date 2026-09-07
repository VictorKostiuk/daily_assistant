require "rails_helper"

RSpec.describe User, type: :model do
  it "is valid with a first name, last name, and valid devise attributes" do
    user = build(:user)
    expect(user).to be_valid
  end

  it "requires a first name of at least 2 characters" do
    user = build(:user, first_name: "A")
    expect(user).not_to be_valid
    expect(user.errors[:first_name]).to be_present
  end

  it "requires a last name of at least 2 characters" do
    user = build(:user, last_name: "B")
    expect(user).not_to be_valid
    expect(user.errors[:last_name]).to be_present
  end

  it "defaults to the member role" do
    expect(build(:user).role).to eq("member")
  end

  describe "#google_integration" do
    it "returns the user's connected Google integration" do
      user = create(:user)
      integration = create(:user_integration, user: user)

      expect(user.google_integration).to eq(integration)
    end

    it "returns nil when no Google integration exists" do
      expect(create(:user).google_integration).to be_nil
    end
  end
end
