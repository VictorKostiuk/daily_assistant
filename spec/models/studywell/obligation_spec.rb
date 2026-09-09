require "rails_helper"

RSpec.describe Studywell::Obligation, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:studywell_obligation)).to be_valid
  end

  it "defaults to open status" do
    expect(create(:studywell_obligation)).to be_open
  end

  it "keeps kind and status integers stable" do
    expect(described_class.kinds).to eq("assignment" => 0, "exam" => 1, "study_task" => 2)
    expect(described_class.statuses).to eq("open" => 0, "done" => 1)
    expect(described_class.importances).to eq("low" => 0, "normal" => 1, "high" => 2)
  end

  describe "#remaining_minutes" do
    it "is the rounded-up uncompleted fraction when estimate and progress are known" do
      obligation = build(:studywell_obligation, estimated_minutes: 10, progress_percent: 33)
      expect(obligation.remaining_minutes).to eq(7)
    end

    it "is zero when progress is 100 and does not depend on completion" do
      obligation = build(:studywell_obligation, :done, estimated_minutes: 60, progress_percent: 100)
      expect(obligation.remaining_minutes).to eq(0)
    end

    it "is null when either estimate or progress is unknown" do
      expect(build(:studywell_obligation, estimated_minutes: 60, progress_percent: nil).remaining_minutes).to be_nil
      expect(build(:studywell_obligation, estimated_minutes: nil, progress_percent: 40).remaining_minutes).to be_nil
    end
  end

  it "rejects an assignment interval and an exam deadline" do
    assignment = build(:studywell_obligation, starts_at: Time.iso8601("2026-10-01T09:00:00Z"), ends_at: Time.iso8601("2026-10-01T10:00:00Z"))
    expect(assignment).not_to be_valid
    expect(assignment.errors[:starts_at]).to eq([ "is invalid" ])

    exam = build(:studywell_obligation, :exam, due_at: Time.iso8601("2026-10-01T09:00:00Z"))
    expect(exam).not_to be_valid
    expect(exam.errors[:due_at]).to eq([ "is invalid" ])
  end

  it "rejects a study task whose planned end is after its due_at" do
    obligation = build(
      :studywell_obligation,
      :study_task,
      due_at: Time.iso8601("2026-10-01T10:00:00Z"),
      starts_at: Time.iso8601("2026-10-01T09:00:00Z"),
      ends_at: Time.iso8601("2026-10-01T11:00:00Z")
    )
    expect(obligation).not_to be_valid
    expect(obligation.errors[:ends_at]).to eq([ "is invalid" ])
  end
end
