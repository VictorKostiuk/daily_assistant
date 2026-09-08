require "rails_helper"

RSpec.describe "API v1 AI messages", type: :request do
  OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions".freeze
  LEAKED_TOKEN = "sk-leaked-token-abc123".freeze

  def json
    JSON.parse(response.body)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def issue_token_for(user)
    ApiToken.issue!(user: user).first
  end

  def error_envelope(code:, message:, details: {})
    { "error" => { "code" => code, "message" => message, "details" => details } }
  end

  def stub_openrouter_body(body)
    stub_request(:post, OPENROUTER_CHAT_URL).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: body.to_json
    )
  end

  def stub_openrouter_content(content)
    stub_openrouter_body("choices" => [ { "message" => { "content" => content } } ])
  end

  def post_message(params)
    post "/api/v1/ai/messages", params: params, headers: bearer(token), as: :json
  end

  let(:user) { create(:user) }
  let(:token) { issue_token_for(user) }
  let(:other) { create(:user) }

  describe "POST /api/v1/ai/messages" do
    it "returns 200 with the four source fields, the row id, and the configured model" do
      stub_openrouter_content("Sure — here is a three-step plan")

      post_message({
        message: "Help me plan",
        context_type: "study",
        source_app: "daily-study",
        source_entity_type: "StudyTask",
        source_entity_id: "8e3abc"
      })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        "id" => row.id,
        "message" => "Sure — here is a three-step plan",
        "model" => Rails.application.config.x.open_router.model,
        "context_type" => "study",
        "source_app" => "daily-study",
        "source_entity_type" => "StudyTask",
        "source_entity_id" => "8e3abc"
      )
      expect(json).not_to have_key("data")
    end

    it "emits only the supplied non-null source fields" do
      stub_openrouter_content("ok")

      post_message({ message: "Hi", source_app: "daily-study", context_type: nil })

      expect(response).to have_http_status(:ok)
      expect(json.keys).to contain_exactly("id", "message", "model", "source_app")
      expect(json["source_app"]).to eq("daily-study")
    end

    it "sends no response_format key and temperature 0.7 on the AI path" do
      stub_openrouter_content("ok")

      post_message({ message: "Hi" })

      expect(response).to have_http_status(:ok)
      expect(a_request(:post, OPENROUTER_CHAT_URL).with { |req|
        body = JSON.parse(req.body)
        !body.key?("response_format") && body["temperature"] == 0.7
      }).to have_been_made
    end

    it "scopes the row to the caller and does not touch another user's rows" do
      other_row = create(:action_execution, user: other)
      stub_openrouter_content("ok")

      post_message({ message: "Hi" })

      row = ActionExecution.find(json["id"])
      expect(row.user_id).to eq(user.id)
      expect(other.action_executions.reload.pluck(:id)).to eq([ other_row.id ])
    end

    it "records processing before the provider call and finishes succeeded" do
      stub_request(:post, OPENROUTER_CHAT_URL).to_return do
        row = user.action_executions.order(:id).last
        expect(row).to be_present
        expect(row.status).to eq("processing")
        expect(row.started_at).to be_present
        expect(row.completed_at).to be_nil
        {
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { "choices" => [ { "message" => { "content" => "ok" } } ] }.to_json
        }
      end

      post_message({ message: "Hi" })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:ok)
      expect(row.status).to eq("succeeded")
      expect(row.action_type).to eq("ai.message")
      expect(row.source).to eq("api")
      expect(row.started_at).to be_present
      expect(row.completed_at).to be_present
      expect(row.duration_ms).to eq(((row.completed_at - row.started_at) * 1000).round)
      expect(row.error_message).to be_nil
    end

    it "collapses whitespace then truncates display_text to 120 characters" do
      stub_openrouter_content("ok")
      prompt = ("a" * 50) + "  \n  " + ("b" * 80)

      post_message({ message: prompt })

      row = user.action_executions.order(:id).last
      collapsed = prompt.gsub(/\s+/, " ")[0, 120]
      expect(row.display_text).to eq(collapsed)
      expect(row.display_text.length).to eq(120)
    end

    it "stores a 10,000-character prompt as exactly 120 display_text characters" do
      stub_openrouter_content("ok")

      post_message({ message: "a" * 10_000 })

      row = user.action_executions.order(:id).last
      expect(row.display_text).to eq("a" * 120)
      expect(row.display_text.length).to eq(120)
    end

    it "redacts message from the request parameter log without changing handling" do
      marker = "UNIQUE_LOG_MARKER_PROMPT_ZX7"
      stub_openrouter_content("ok")

      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      logger.level = Logger::INFO
      previous_logger = ActionController::Base.logger
      ActionController::Base.logger = logger

      begin
        post_message({ message: marker })
      ensure
        ActionController::Base.logger = previous_logger
      end

      logs = io.string
      parameter_lines = logs.lines.select { |line| line.include?("Parameters:") }
      expect(response).to have_http_status(:ok)
      expect(parameter_lines).not_to be_empty, "expected a Parameters: log line, got:\n#{logs}"
      expect(parameter_lines.join).to include("[FILTERED]"), "log was:\n#{logs}"
      expect(parameter_lines.join).not_to include(marker), "log was:\n#{logs}"

      expect(a_request(:post, OPENROUTER_CHAT_URL).with { |req|
        JSON.parse(req.body)["messages"].any? { |entry| entry["content"] == marker }
      }).to have_been_made

      row = user.action_executions.order(:id).last
      expect(row.display_text).to eq(marker)
    end

    it "does not persist the prompt or the answer except the display_text preview" do
      stub_openrouter_content("UNIQUE_ANSWER_TOKEN_ZX9 the plan")

      post_message({ message: "UNIQUE_PROMPT_TOKEN_QW8 please advise" })

      row = user.action_executions.order(:id).last.reload
      expect(row.input_data).to eq({})
      expect(row.output_data).to eq({})
      expect(row.display_text).to include("UNIQUE_PROMPT_TOKEN_QW8")
      expect(row.display_text).not_to include("UNIQUE_ANSWER_TOKEN_ZX9")
      row.attributes.each do |name, value|
        next if name == "display_text"

        serialized = value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
        expect(serialized).not_to include("UNIQUE_PROMPT_TOKEN_QW8"), "#{name} leaked the prompt"
        expect(serialized).not_to include("UNIQUE_ANSWER_TOKEN_ZX9"), "#{name} leaked the answer"
      end
    end

    it "rejects a missing message with 422, no row, and no provider" do
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post_message({}) }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_error")
      expect(json.dig("error", "details")).to include("message")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "rejects a blank message with 422, no row, and no provider" do
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post_message({ message: "   " }) }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("message")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "rejects a non-String message with 422, no row, and no provider" do
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post_message({ message: 12 }) }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("message")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "rejects a 10,001-character message with 422, no row, and no provider" do
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post_message({ message: "a" * 10_001 }) }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("message")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    %w[conversation_id tools model user_id].each do |field|
      it "rejects unknown field #{field} with 422, no row, and no provider" do
        expect(Integrations::OpenRouter::Client).not_to receive(:new)

        expect { post_message({ message: "Hi", field => "nope" }) }.not_to change(ActionExecution, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_error")
        expect(json.dig("error", "details")).to include(field)
        expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
      end
    end

    it "rejects an invalid context_type with 422, no row, and no provider" do
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post_message({ message: "Hi", context_type: "hobby" }) }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("context_type")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "rejects a non-string source value with 422, no row, and no provider" do
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post_message({ message: "Hi", source_app: [ "daily-study" ] }) }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("source_app")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "does not authenticate from a Devise session cookie without a bearer token" do
      sign_in user
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post "/api/v1/ai/messages", params: { message: "Hi" }, as: :json }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(error_envelope(code: "unauthorized", message: "Unauthorized"))
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "returns 500 and makes zero provider calls when the initial row write fails" do
      allow_any_instance_of(ActionExecution).to receive(:save!).and_raise(ActiveRecord::ActiveRecordError, "disk full")
      expect(Integrations::OpenRouter::Client).not_to receive(:new)

      expect { post_message({ message: "Hi" }) }.not_to change(ActionExecution, :count)

      expect(response).to have_http_status(:internal_server_error)
      expect(response.media_type).to eq("application/json")
      expect(json).to eq(error_envelope(code: "internal_error", message: "Request failed"))
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "returns 500 and calls the provider exactly once when completing the row fails after success" do
      stub_openrouter_content("ok")
      allow_any_instance_of(ActionExecution).to receive(:update!).and_raise(ActiveRecord::ActiveRecordError, "disk full")

      post_message({ message: "Hi" })

      expect(response).to have_http_status(:internal_server_error)
      expect(json.dig("error", "code")).to eq("internal_error")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).to have_been_made.once
    end

    it "returns 503 for NotConfigured and marks the row failed" do
      allow_any_instance_of(Integrations::OpenRouter::Client).to receive(:chat)
        .and_raise(Integrations::OpenRouter::Client::NotConfigured, "OPEN_ROUTER_KEY is missing")

      expect { post_message({ message: "Hi" }) }.to change { user.action_executions.count }.by(1)

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:service_unavailable)
      expect(json).to eq(error_envelope(code: "integration_unavailable", message: "Integration is unavailable"))
      expect(row.status).to eq("failed")
      expect(row.error_message).to eq("integration_unavailable")
      expect(a_request(:post, OPENROUTER_CHAT_URL)).not_to have_been_made
    end

    it "returns 502 for a provider timeout and marks the row failed" do
      stub_request(:post, OPENROUTER_CHAT_URL).to_raise(Faraday::TimeoutError.new("timeout"))

      post_message({ message: "Hi" })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(row.status).to eq("failed")
      expect(row.error_message).to eq("provider_error")
    end

    it "returns 502 for empty content and marks the row failed" do
      stub_openrouter_content("")

      post_message({ message: "Hi" })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(row.status).to eq("failed")
      expect(row.error_message).to eq("provider_error")
    end

    it "returns 502 for non-String content and marks the row failed" do
      stub_openrouter_body("choices" => [ { "message" => { "content" => { "text" => "nope" } } } ])

      post_message({ message: "Hi" })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(row.status).to eq("failed")
    end

    it "does not leak provider error text into the response or error_message" do
      stub_openrouter_body(
        "choices" => [ { "message" => { "content" => "" } } ],
        "error" => { "message" => LEAKED_TOKEN }
      )

      post_message({ message: "Hi" })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:bad_gateway)
      expect(response.body).not_to include(LEAKED_TOKEN)
      expect(row.error_message).to eq("provider_error")
      expect(row.error_message).not_to include(LEAKED_TOKEN)
    end

    [
      [ "a top-level JSON array", [ { "choices" => [] } ] ],
      [ "a top-level JSON scalar", "not-an-object" ],
      [ "a response with no choices", { "id" => "x" } ],
      [ "a response with empty choices", { "choices" => [] } ],
      [ "a response whose choices is not an array", { "choices" => { "message" => {} } } ],
      [ "a response with no message", { "choices" => [ { "index" => 0 } ] } ],
      [ "a response with no content", { "choices" => [ { "message" => { "role" => "assistant" } } ] } ]
    ].each do |label, body|
      it "returns 502 provider_error for #{label} and marks the row failed" do
        stub_openrouter_body(body)

        post_message({ message: "Hi" })

        row = user.action_executions.order(:id).last
        expect(response).to have_http_status(:bad_gateway)
        expect(response.media_type).to eq("application/json")
        expect(json.dig("error", "code")).to eq("provider_error")
        expect(row.status).to eq("failed")
        expect(row.error_message).to eq("provider_error")
      end
    end

    it "returns 502 provider_error when error is not a Hash and there is no usable content" do
      stub_openrouter_body("choices" => [], "error" => "rate limited by upstream sk-XYZ")

      post_message({ message: "Hi" })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:bad_gateway)
      expect(json.dig("error", "code")).to eq("provider_error")
      expect(row.status).to eq("failed")
      expect(row.error_message).to eq("provider_error")
    end

    it "returns 500 internal_error in the JSON envelope for an unrelated StandardError and does not leave the row processing" do
      allow_any_instance_of(Integrations::OpenRouter::Client).to receive(:chat)
        .and_raise(RuntimeError, "unrelated boom")

      post_message({ message: "Hi" })

      row = user.action_executions.order(:id).last
      expect(response).to have_http_status(:internal_server_error)
      expect(response.media_type).to eq("application/json")
      expect(json).to eq(error_envelope(code: "internal_error", message: "Request failed"))
      expect(response.body).not_to include("<html")
      expect(row.status).to eq("failed")
      expect(row.error_message).to eq("internal_error")
      expect(row.status).not_to eq("processing")
    end

    it "escapes markup from display_text on the existing admin surface" do
      stub_openrouter_content("ok")

      post_message({ message: "<script>alert(1)</script>" })
      expect(response).to have_http_status(:ok)

      sign_in create(:user, :admin)
      get admin_user_path(user)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
      expect(response.body).not_to include("<script>alert(1)</script>")
    end

    it "shows error_message instead of the preview on a failed admin row" do
      stub_openrouter_content("")

      post_message({ message: "PROMPT_PREVIEW_UNIQUE" })
      expect(response).to have_http_status(:bad_gateway)

      sign_in create(:user, :admin)
      get admin_user_path(user)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("provider_error")
      expect(response.body).not_to include("PROMPT_PREVIEW_UNIQUE")
    end
  end
end
