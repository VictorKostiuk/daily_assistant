require "rails_helper"

RSpec.describe Integrations::Google::UpdateEvent do
  let(:event) do
    Integrations::OpenRouter::EventParsing::Event.new(
      title: "Dinner with Anna", description: nil, location: nil,
      starts_at: Time.zone.parse("2026-08-10 20:00"), ends_at: Time.zone.parse("2026-08-10 21:00"), all_day: false
    )
  end

  it "does not call Google when metadata is invalid" do
    user = create(:user)
    create(:user_integration, user: user)
    google_event = instance_double(Google::Apis::CalendarV3::Event, id: "gcal_1")
    calendar = instance_double(Google::Apis::CalendarV3::CalendarService)
    allow(calendar).to receive(:update_event).and_return(google_event)
    allow(Integrations::Google::Client).to receive(:new).and_return(
      instance_double(Integrations::Google::Client, calendar: calendar)
    )

    expect {
      described_class.call(user: user, event_id: "gcal_1", event: event, metadata: { "context_type" => "hobby" })
    }.to raise_error(SourceMetadata::Invalid)

    expect(calendar).not_to have_received(:update_event)
  end
end
