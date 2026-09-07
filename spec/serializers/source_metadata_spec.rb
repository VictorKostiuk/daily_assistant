require "rails_helper"

RSpec.describe SourceMetadata do
  let(:flat) do
    {
      "context_type" => "study",
      "source_app" => "daily-study",
      "source_entity_type" => "StudyTask",
      "source_entity_id" => "8e3abc"
    }
  end

  describe ".dump" do
    it "nests the public fields under the reserved source key" do
      expect(described_class.dump(flat)).to eq("source" => flat)
    end

    it "accepts a partial payload" do
      expect(described_class.dump("source_app" => "daily-study")).to eq(
        "source" => { "source_app" => "daily-study" }
      )
    end

    it "returns an empty hash when metadata is omitted" do
      expect(described_class.dump(nil)).to eq({})
      expect(described_class.dump({})).to eq({})
    end

    it "rejects an unknown key under source with the validation_error envelope" do
      expect {
        described_class.dump("context_type" => "study", "source_ref" => "oops")
      }.to raise_error(described_class::Invalid) { |error|
        expect(error.message).to eq("Request is invalid")
        expect(error.details).to eq("source_ref" => [ "is unknown" ])
        expect(error.error_envelope).to eq(
          "error" => {
            "code" => "validation_error",
            "message" => "Request is invalid",
            "details" => { "source_ref" => [ "is unknown" ] }
          }
        )
        expect(error.http_status).to eq(:unprocessable_content)
      }
    end

    it "rejects an invalid context_type with the validation_error envelope" do
      expect {
        described_class.dump("context_type" => "hobby")
      }.to raise_error(described_class::Invalid) { |error|
        expect(error.details).to eq("context_type" => [ "is not included in the list" ])
        expect(error.error_envelope.dig("error", "code")).to eq("validation_error")
        expect(error.http_status).to eq(:unprocessable_content)
      }
    end

    it "rejects non-Hash input as Invalid, not a raw NoMethodError" do
      expect {
        described_class.dump(Object.new)
      }.to raise_error(described_class::Invalid) { |error|
        expect(error.details).to eq("metadata" => [ "is invalid" ])
      }

      expect {
        described_class.dump(ActionController::Parameters.new("context_type" => "study"))
      }.to raise_error(described_class::Invalid)
    end

    it "rejects remindable_type and remindable_id as unknown source keys" do
      expect {
        described_class.dump("remindable_type" => "StudyTask", "remindable_id" => "8e3abc")
      }.to raise_error(described_class::Invalid) { |error|
        expect(error.details.keys).to contain_exactly("remindable_type", "remindable_id")
      }
    end

    it "rejects non-string source values instead of coercing or storing them" do
      {
        "source_app" => 12,
        "source_entity_id" => 8e3,
        "source_entity_type" => true,
        "context_type" => [ "study" ]
      }.each do |field, value|
        expect {
          described_class.dump(field => value)
        }.to raise_error(described_class::Invalid) { |error|
          expect(error.details).to eq(field => [ "is invalid" ])
          expect(error.error_envelope.dig("error", "code")).to eq("validation_error")
        }
      end
    end

    it "rejects a blank source string rather than storing or clearing silently" do
      expect {
        described_class.dump("source_app" => "  ")
      }.to raise_error(described_class::Invalid) { |error|
        expect(error.details).to eq("source_app" => [ "is invalid" ])
      }
    end

    it "keeps a numeric-looking source_entity_id as a string" do
      expect(described_class.dump("source_entity_id" => "9001")).to eq(
        "source" => { "source_entity_id" => "9001" }
      )
    end

    %w[life study work global].each do |context_type|
      it "accepts context_type #{context_type}" do
        expect(described_class.dump("context_type" => context_type)).to eq(
          "source" => { "context_type" => context_type }
        )
      end
    end
  end

  describe ".load" do
    it "flattens stored source metadata into the public shape" do
      expect(described_class.load("source" => flat)).to eq(flat)
    end

    it "returns an empty hash when source is missing" do
      expect(described_class.load(nil)).to eq({})
      expect(described_class.load({})).to eq({})
      expect(described_class.load("source" => {})).to eq({})
    end

    it "omits unknown stored keys from the public shape" do
      expect(
        described_class.load("source" => flat.merge("extra" => "drop-me"))
      ).to eq(flat)
    end
  end

  describe ".merge" do
    let(:existing) do
      {
        "source" => {
          "context_type" => "work",
          "source_app" => "daily-work",
          "source_entity_type" => "WorkTask",
          "source_entity_id" => "task-1"
        },
        "internal_note" => "keep-me"
      }
    end

    it "replaces only the supplied source field and preserves the rest plus unrelated keys" do
      merged = described_class.merge(existing, "source_app" => "daily-study")

      expect(merged["internal_note"]).to eq("keep-me")
      expect(merged["source"]).to eq(
        "context_type" => "work",
        "source_app" => "daily-study",
        "source_entity_type" => "WorkTask",
        "source_entity_id" => "task-1"
      )
    end

    it "clears a field given explicit nil without dropping omitted source keys" do
      merged = described_class.merge(existing, "source_app" => nil)

      expect(merged["internal_note"]).to eq("keep-me")
      expect(merged["source"]).to eq(
        "context_type" => "work",
        "source_entity_type" => "WorkTask",
        "source_entity_id" => "task-1"
      )
      expect(merged["source"]).not_to have_key("source_app")
    end

    it "does not treat an omitted field as a clear" do
      merged = described_class.merge(existing, "context_type" => "study")

      expect(merged["source"]["source_app"]).to eq("daily-work")
      expect(merged["source"]["context_type"]).to eq("study")
    end

    it "drops the source key entirely when the last field is cleared" do
      merged = described_class.merge(
        { "source" => { "source_app" => "daily-work" }, "internal_note" => "keep-me" },
        "source_app" => nil
      )

      expect(merged).to eq("internal_note" => "keep-me")
    end

    it "rejects a non-string patch value before mutating existing metadata" do
      snapshot = existing.deep_dup

      expect {
        described_class.merge(existing, "source_app" => [ "x" ])
      }.to raise_error(described_class::Invalid) { |error|
        expect(error.details).to eq("source_app" => [ "is invalid" ])
      }
      expect(existing).to eq(snapshot)
    end
  end
end
