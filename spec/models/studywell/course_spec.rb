require "rails_helper"

RSpec.describe Studywell::Course, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:studywell_course)).to be_valid
  end

  it "requires a name" do
    course = build(:studywell_course, name: nil)
    expect(course).not_to be_valid
    expect(course.errors[:name]).to be_present
  end

  it "accepts a six-digit colour and rejects other values" do
    expect(build(:studywell_course, colour: "#AaBb09")).to be_valid
    expect(build(:studywell_course, colour: nil)).to be_valid

    course = build(:studywell_course, colour: "#fff")
    expect(course).not_to be_valid
    expect(course.errors[:colour]).to be_present
  end

  it "requires active_from to be on or before active_until when both are set" do
    course = build(:studywell_course, active_from: Date.iso8601("2026-12-01"), active_until: Date.iso8601("2026-01-01"))
    expect(course).not_to be_valid
    expect(course.errors[:active_until]).to eq([ "is invalid" ])
  end

  it "restricts destroy while obligations exist" do
    course = create(:studywell_course)
    create(:studywell_obligation, user: course.user, course: course)

    expect { course.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(Studywell::Course.exists?(course.id)).to be(true)
  end
end
