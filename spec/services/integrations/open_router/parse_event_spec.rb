require "rails_helper"

RSpec.describe Integrations::OpenRouter::ParseEvent do
  def stub_openrouter_chat(content)
    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { choices: [ { message: { content: content } } ] }.to_json
    )
  end

  it "builds an Event from the model's JSON response" do
    stub_openrouter_chat({
      title: "Dinner with Anna",
      description: "Book a table for two",
      location: "Trattoria da Mario",
      start_time: "2026-08-10T19:00:00",
      end_time: "2026-08-10T20:00:00",
      all_day: false
    }.to_json)

    event = described_class.call(text: "dinner with Anna", time_zone: "Europe/Rome")

    expect(event.title).to eq("Dinner with Anna")
    expect(event.location).to eq("Trattoria da Mario")
    expect(event.all_day).to be(false)
    expect(event.starts_at.strftime("%Y-%m-%d %H:%M")).to eq("2026-08-10 19:00")
  end

  it "defaults to a one-hour duration when no end time is given" do
    stub_openrouter_chat({
      title: "Quick call", description: nil, location: nil,
      start_time: "2026-08-10T19:00:00", end_time: nil, all_day: false
    }.to_json)

    event = described_class.call(text: "quick call", time_zone: "Europe/Rome")

    expect(event.ends_at - event.starts_at).to eq(1.hour)
  end

  it "raises UnparseableResponse when the model returns no JSON object" do
    stub_openrouter_chat("sorry, I cannot help with that")

    expect {
      described_class.call(text: "gibberish", time_zone: "Europe/Rome")
    }.to raise_error(Integrations::OpenRouter::EventParsing::UnparseableResponse)
  end

  it "sends response_format json_object and temperature 0 on the extraction path" do
    stub_openrouter_chat({
      title: "Dinner with Anna",
      description: nil,
      location: nil,
      start_time: "2026-08-10T19:00:00",
      end_time: "2026-08-10T20:00:00",
      all_day: false
    }.to_json)

    described_class.call(text: "dinner with Anna", time_zone: "Europe/Rome")

    expect(a_request(:post, "https://openrouter.ai/api/v1/chat/completions").with { |req|
      body = JSON.parse(req.body)
      body["response_format"] == { "type" => "json_object" } && body["temperature"] == 0
    }).to have_been_made
  end

  it "raises UnparseableResponse when the response has no usable start time" do
    stub_openrouter_chat({ title: "No time", description: nil, location: nil, start_time: nil, end_time: nil, all_day: false }.to_json)

    expect {
      described_class.call(text: "no time", time_zone: "Europe/Rome")
    }.to raise_error(Integrations::OpenRouter::EventParsing::UnparseableResponse)
  end
end
