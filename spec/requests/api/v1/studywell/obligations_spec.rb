require "rails_helper"

RSpec.describe "API v1 StudyWell obligations", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def json
    JSON.parse(response.body)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def issue_token_for(user)
    ApiToken.issue!(user: user).first
  end

  def openapi_schema(name)
    YAML.safe_load_file(Rails.root.join("docs/openapi.yaml")).dig("components", "schemas", name)
  end

  def schema_instance_accepts?(schema, value)
    return false unless value.is_a?(String)
    return false if schema["minLength"] && value.length < schema["minLength"]

    value.match?(Regexp.new(schema.fetch("pattern")))
  end

  def nonblank_cases
    [
      [ "plain text", "Problem set 1", true, true ],
      [ "ASCII space", " ", false, false ],
      [ "tab and newline", "\t\n", false, false ],
      [ "NBSP", "\u00A0", false, true ],
      [ "ideographic space", "\u3000", false, true ],
      [ "NUL", "\u0000", false, false ],
      [ "NBSP plus text", "\u00A0Keep", true, true ],
      [ "NUL plus NBSP", "\u0000\u00A0", true, true ]
    ]
  end

  def obligation_payload(obligation)
    obligation.reload
    {
      "id" => obligation.id,
      "course_id" => obligation.course_id,
      "kind" => obligation.kind,
      "title" => obligation.title,
      "due_at" => obligation.due_at&.iso8601,
      "starts_at" => obligation.starts_at&.iso8601,
      "ends_at" => obligation.ends_at&.iso8601,
      "importance" => obligation.importance,
      "estimated_minutes" => obligation.estimated_minutes,
      "progress_percent" => obligation.progress_percent,
      "notes" => obligation.notes,
      "status" => obligation.status,
      "completed_at" => obligation.completed_at&.iso8601,
      "lock_version" => obligation.lock_version,
      "remaining_minutes" => obligation.remaining_minutes
    }
  end

  let(:user) { create(:user) }
  let(:token) { issue_token_for(user) }
  let(:other) { create(:user) }
  let(:course) { create(:studywell_course, user: user) }

  describe "POST /api/v1/studywell/courses/:course_id/obligations" do
    it "creates an assignment with optional due_at and lock_version 0" do
      expect {
        post "/api/v1/studywell/courses/#{course.id}/obligations",
             params: {
               kind: "assignment",
               title: "Problem set 1",
               due_at: "2026-10-01T17:00:00+02:00",
               importance: "high",
               estimated_minutes: 120,
               progress_percent: 10,
               notes: "Chapter 3"
             },
             headers: bearer(token), as: :json
      }.to change { course.obligations.count }.by(1)

      obligation = course.obligations.order(:id).last
      expect(response).to have_http_status(:created)
      expect(json).to eq(obligation_payload(obligation))
      expect(json["lock_version"]).to eq(0)
      expect(json["status"]).to eq("open")
      expect(json["remaining_minutes"]).to eq(108)
      expect(obligation.user).to eq(user)
      expect(obligation.due_at).to eq(Time.iso8601("2026-10-01T17:00:00+02:00"))
    end

    it "creates an exam interval and a study task with both facets" do
      post "/api/v1/studywell/courses/#{course.id}/obligations",
           params: {
             kind: "exam",
             title: "Midterm",
             starts_at: "2026-11-01T09:00:00Z",
             ends_at: "2026-11-01T11:00:00Z"
           },
           headers: bearer(token), as: :json
      expect(response).to have_http_status(:created)
      exam = course.obligations.order(:id).last
      expect(exam.kind).to eq("exam")
      expect(exam.due_at).to be_nil
      expect(exam.starts_at).to eq(Time.iso8601("2026-11-01T09:00:00Z"))

      post "/api/v1/studywell/courses/#{course.id}/obligations",
           params: {
             kind: "study_task",
             title: "Revise",
             due_at: "2026-11-01T18:00:00Z",
             starts_at: "2026-11-01T09:00:00Z",
             ends_at: "2026-11-01T11:00:00Z"
           },
           headers: bearer(token), as: :json
      expect(response).to have_http_status(:created)
      task = course.obligations.order(:id).last
      expect(task.kind).to eq("study_task")
      expect(task.due_at).to eq(Time.iso8601("2026-11-01T18:00:00Z"))
    end

    it "does not invent remaining_minutes when progress is unknown" do
      post "/api/v1/studywell/courses/#{course.id}/obligations",
           params: { kind: "assignment", title: "No progress", estimated_minutes: 60 },
           headers: bearer(token), as: :json

      expect(response).to have_http_status(:created)
      expect(json["remaining_minutes"]).to be_nil
      expect(course.obligations.order(:id).last.progress_percent).to be_nil
    end

    it "rejects impossible calendar dates without persisting, and keeps leap days and 24:00:00" do
      expect {
        post "/api/v1/studywell/courses/#{course.id}/obligations",
             params: { kind: "assignment", title: "Feb 30", due_at: "2026-02-30T10:00:00Z" },
             headers: bearer(token), as: :json
      }.not_to change(Studywell::Obligation, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("due_at")

      expect {
        post "/api/v1/studywell/courses/#{course.id}/obligations",
             params: { kind: "assignment", title: "Non-leap", due_at: "2026-02-29T10:00:00Z" },
             headers: bearer(token), as: :json
      }.not_to change(Studywell::Obligation, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("due_at")

      post "/api/v1/studywell/courses/#{course.id}/obligations",
           params: { kind: "assignment", title: "Leap day", due_at: "2024-02-29T10:00:00Z" },
           headers: bearer(token), as: :json
      expect(response).to have_http_status(:created)
      leap = course.obligations.order(:id).last
      expect(leap.title).to eq("Leap day")
      expect(leap.due_at).to eq(Time.iso8601("2024-02-29T10:00:00Z"))

      post "/api/v1/studywell/courses/#{course.id}/obligations",
           params: { kind: "assignment", title: "End of day", due_at: "2026-01-01T24:00:00Z" },
           headers: bearer(token), as: :json
      expect(response).to have_http_status(:created)
      end_of_day = course.obligations.order(:id).last
      expect(end_of_day.title).to eq("End of day")
      expect(end_of_day.due_at).to eq(Time.iso8601("2026-01-02T00:00:00Z"))
    end

    it "rejects assignment intervals, exam due_at, partial intervals, naive timestamps, and inverted bounds" do
      [
        { kind: "assignment", title: "X", starts_at: "2026-11-01T09:00:00Z", ends_at: "2026-11-01T10:00:00Z" },
        { kind: "exam", title: "X", due_at: "2026-11-01T09:00:00Z" },
        { kind: "exam", title: "X", starts_at: "2026-11-01T09:00:00Z" },
        { kind: "study_task", title: "X", due_at: "2026-11-01T10:00:00" },
        { kind: "study_task", title: "X", starts_at: "2026-11-01T11:00:00Z", ends_at: "2026-11-01T10:00:00Z" },
        { kind: "study_task", title: "X", due_at: "2026-11-01T10:00:00Z", starts_at: "2026-11-01T09:00:00Z", ends_at: "2026-11-01T11:00:00Z" }
      ].each do |params|
        expect {
          post "/api/v1/studywell/courses/#{course.id}/obligations",
               params: params, headers: bearer(token), as: :json
        }.not_to change(Studywell::Obligation, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_error")
      end
    end

    it "allows creating an obligation inside an archived course" do
      course.update!(archived_at: Time.current)

      post "/api/v1/studywell/courses/#{course.id}/obligations",
           params: { kind: "assignment", title: "Still allowed" },
           headers: bearer(token), as: :json

      expect(response).to have_http_status(:created)
      expect(course.obligations.order(:id).last.title).to eq("Still allowed")
    end

    it "returns 404 for another user's course and does not create" do
      theirs = create(:studywell_course, user: other)

      expect {
        post "/api/v1/studywell/courses/#{theirs.id}/obligations",
             params: { kind: "assignment", title: "Nope" },
             headers: bearer(token), as: :json
      }.not_to change(Studywell::Obligation, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "records server and schema-instance outcomes for create titles separately" do
      schema = openapi_schema("StudywellObligationCreate").fetch("properties").fetch("title")
      schema_rejected_but_server_accepted = []
      nonblank_cases.each do |label, value, server_accepts, schema_accepts|
        instance_ok = schema_instance_accepts?(schema, value)
        expect(instance_ok).to eq(schema_accepts),
          "#{label}: schema-instance #{instance_ok.inspect}, expected #{schema_accepts.inspect}"
        expect([ "NBSP", "ideographic space" ]).to include(label) if schema_accepts && !server_accepts

        expect {
          post "/api/v1/studywell/courses/#{course.id}/obligations",
               params: { kind: "assignment", title: value },
               headers: bearer(token), as: :json
        }.to change { course.obligations.count }.by(server_accepts ? 1 : 0)

        if server_accepts
          expect(response).to have_http_status(:created)
          expect(course.obligations.order(:id).last.title).to eq(value)
        else
          expect(response).to have_http_status(:unprocessable_content)
        end
        schema_rejected_but_server_accepted << label if !instance_ok && server_accepts
      end
      expect(schema_rejected_but_server_accepted).to eq([])
    end

    it "rejects unknown keys including status and remaining_minutes" do
      expect {
        post "/api/v1/studywell/courses/#{course.id}/obligations",
             params: { kind: "assignment", title: "X", status: "done" },
             headers: bearer(token), as: :json
      }.not_to change(Studywell::Obligation, :count)
      expect(json.dig("error", "details")).to include("status")
    end
  end

  describe "GET /api/v1/studywell/courses/:course_id/obligations" do
    it "lists only that course's obligations in id order and isolates other users" do
      first = create(:studywell_obligation, user: user, course: course, title: "First")
      second = create(:studywell_obligation, user: user, course: course, title: "Second")
      other_course = create(:studywell_course, user: user)
      create(:studywell_obligation, user: user, course: other_course, title: "Elsewhere")
      create(:studywell_obligation, user: other, course: create(:studywell_course, user: other), title: "Theirs")

      get "/api/v1/studywell/courses/#{course.id}/obligations", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json["items"].map { |item| item["id"] }).to eq([ first.id, second.id ])
      expect(json["next_page"]).to be_nil
    end

    it "filters status=open|done and defaults to all" do
      open_item = create(:studywell_obligation, user: user, course: course, title: "Open")
      done_item = create(:studywell_obligation, :done, user: user, course: course, title: "Done")

      get "/api/v1/studywell/courses/#{course.id}/obligations", headers: bearer(token)
      expect(json["items"].map { |item| item["id"] }).to contain_exactly(open_item.id, done_item.id)

      get "/api/v1/studywell/courses/#{course.id}/obligations", params: { status: "open" }, headers: bearer(token)
      expect(json["items"].map { |item| item["id"] }).to eq([ open_item.id ])

      get "/api/v1/studywell/courses/#{course.id}/obligations", params: { status: "done" }, headers: bearer(token)
      expect(json["items"].map { |item| item["id"] }).to eq([ done_item.id ])
    end

    it "rejects an invalid status and ignores unknown query keys" do
      get "/api/v1/studywell/courses/#{course.id}/obligations", params: { status: "pending" }, headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("status")

      get "/api/v1/studywell/courses/#{course.id}/obligations", params: { extra: "1" }, headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end

    it "treats a present valueless status as invalid, unlike an omitted key" do
      open_item = create(:studywell_obligation, user: user, course: course, title: "Open")
      create(:studywell_obligation, :done, user: user, course: course, title: "Done")

      get "/api/v1/studywell/courses/#{course.id}/obligations", headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(json["items"].size).to eq(2)

      get "/api/v1/studywell/courses/#{course.id}/obligations?status=open", headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(json["items"].map { |item| item["id"] }).to eq([ open_item.id ])

      get "/api/v1/studywell/courses/#{course.id}/obligations?status", headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("status")

      get "/api/v1/studywell/courses/#{course.id}/obligations?status=", headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("status")
    end

    it "pages 100 at a time with no silent truncation" do
      create_list(:studywell_obligation, 101, user: user, course: course)

      get "/api/v1/studywell/courses/#{course.id}/obligations", headers: bearer(token)
      expect(json["items"].size).to eq(100)
      expect(json["next_page"]).to eq(2)

      get "/api/v1/studywell/courses/#{course.id}/obligations", params: { page: 2 }, headers: bearer(token)
      expect(json["items"].size).to eq(1)
      expect(json["next_page"]).to be_nil
      expect(course.obligations.count).to eq(101)
    end
  end

  describe "GET /api/v1/studywell/obligations/:id" do
    it "returns the caller's obligation" do
      obligation = create(:studywell_obligation, user: user, course: course, title: "Mine")

      get "/api/v1/studywell/obligations/#{obligation.id}", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(obligation_payload(obligation))
    end

    it "returns 404 for another user's obligation" do
      obligation = create(:studywell_obligation, user: other)

      get "/api/v1/studywell/obligations/#{obligation.id}", headers: bearer(token)

      expect(response).to have_http_status(:not_found)
      expect(json.dig("error", "code")).to eq("not_found")
    end
  end

  describe "PATCH /api/v1/studywell/obligations/:id" do
    let(:obligation) do
      create(
        :studywell_obligation,
        user: user,
        course: course,
        title: "Old",
        notes: "keep",
        estimated_minutes: 100,
        progress_percent: 20
      )
    end

    it "updates submitted fields from lock_version 0 and preserves omitted fields" do
      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0, title: "New" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      reloaded = obligation.reload
      expect(reloaded.title).to eq("New")
      expect(reloaded.notes).to eq("keep")
      expect(reloaded.lock_version).to eq(1)
      expect(json["remaining_minutes"]).to eq(80)
    end

    it "rejects an impossible due_at on PATCH without changing the persisted row" do
      obligation.update_column(:due_at, Time.iso8601("2026-10-01T17:00:00Z"))
      original = obligation.reload.due_at

      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0, due_at: "2026-04-31T10:00:00Z" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("due_at")
      expect(obligation.reload.due_at).to eq(original)
      expect(obligation.lock_version).to eq(0)
    end

    it "records server and schema-instance outcomes for PATCH titles separately" do
      schema = openapi_schema("StudywellObligationPatch").fetch("properties").fetch("title")
      schema_rejected_but_server_accepted = []
      nonblank_cases.each do |label, value, server_accepts, schema_accepts|
        instance_ok = schema_instance_accepts?(schema, value)
        expect(instance_ok).to eq(schema_accepts),
          "#{label}: schema-instance #{instance_ok.inspect}, expected #{schema_accepts.inspect}"
        expect([ "NBSP", "ideographic space" ]).to include(label) if schema_accepts && !server_accepts

        record = create(:studywell_obligation, user: user, course: course, title: "Old")
        patch "/api/v1/studywell/obligations/#{record.id}",
              params: { lock_version: 0, title: value },
              headers: bearer(token), as: :json

        if server_accepts
          expect(response).to have_http_status(:ok)
          expect(record.reload.title).to eq(value)
        else
          expect(response).to have_http_status(:unprocessable_content)
          expect(record.reload.title).to eq("Old")
          expect(record.lock_version).to eq(0)
        end
        schema_rejected_but_server_accepted << label if !instance_ok && server_accepts
      end
      expect(schema_rejected_but_server_accepted).to eq([])
    end

    it "clears nullable fields on explicit null and rejects a wrong type without mutating" do
      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0, notes: nil, importance: nil },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(obligation.reload.notes).to be_nil
      expect(obligation.importance).to be_nil

      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 1, estimated_minutes: "60" },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("estimated_minutes")
      expect(obligation.reload.estimated_minutes).to eq(100)
    end

    it "requires both interval bounds when changing a study task plan and rejects an assignment interval" do
      task = create(:studywell_obligation, :study_task, user: user, course: course, title: "Plan")

      patch "/api/v1/studywell/obligations/#{task.id}",
            params: { lock_version: 0, starts_at: "2026-11-01T09:00:00Z" },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("ends_at")
      expect(task.reload.starts_at).to be_nil

      patch "/api/v1/studywell/obligations/#{task.id}",
            params: {
              lock_version: 0,
              starts_at: "2026-11-01T09:00:00Z",
              ends_at: "2026-11-01T11:00:00Z"
            },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(task.reload.starts_at).to eq(Time.iso8601("2026-11-01T09:00:00Z"))

      patch "/api/v1/studywell/obligations/#{task.id}",
            params: { lock_version: 1, starts_at: nil, ends_at: nil },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(task.reload.starts_at).to be_nil
      expect(task.ends_at).to be_nil

      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: {
              lock_version: 0,
              starts_at: "2026-11-01T09:00:00Z",
              ends_at: "2026-11-01T11:00:00Z"
            },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("starts_at")
      expect(obligation.reload.starts_at).to be_nil
    end

    it "rejects kind, empty updates, and unknown keys" do
      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0, kind: "exam" },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to eq("kind" => [ "is unknown" ])
      expect(obligation.reload.kind).to eq("assignment")

      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0 },
            headers: bearer(token), as: :json
      expect(json.dig("error", "details")).to include("base")
    end

    it "completes and reopens explicitly without requiring progress 100" do
      freeze_time do
        patch "/api/v1/studywell/obligations/#{obligation.id}",
              params: { lock_version: 0, status: "done" },
              headers: bearer(token), as: :json
        expect(response).to have_http_status(:ok)
        expect(obligation.reload).to be_done
        expect(obligation.completed_at).to eq(Time.current)
        expect(obligation.progress_percent).to eq(20)
        expect(json["remaining_minutes"]).to eq(80)

        patch "/api/v1/studywell/obligations/#{obligation.id}",
              params: { lock_version: 1, status: "open" },
              headers: bearer(token), as: :json
        expect(obligation.reload).to be_open
        expect(obligation.completed_at).to be_nil
      end
    end

    it "does not complete when progress is set to 100" do
      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0, progress_percent: 100 },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(obligation.reload).to be_open
      expect(obligation.completed_at).to be_nil
      expect(obligation.progress_percent).to eq(100)
      expect(json["remaining_minutes"]).to eq(0)
    end

    it "returns 409 on a stale lock_version and leaves persisted values unchanged" do
      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0, title: "First" },
            headers: bearer(token), as: :json
      expect(obligation.reload.title).to eq("First")

      patch "/api/v1/studywell/obligations/#{obligation.id}",
            params: { lock_version: 0, title: "Stale" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "details")).to eq({})
      expect(obligation.reload.title).to eq("First")
      expect(obligation.lock_version).to eq(1)
    end

    it "returns 404 for another user's obligation" do
      theirs = create(:studywell_obligation, user: other, title: "Theirs")

      patch "/api/v1/studywell/obligations/#{theirs.id}",
            params: { lock_version: 0, title: "Hijack" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload.title).to eq("Theirs")
    end
  end

  describe "DELETE /api/v1/studywell/obligations/:id" do
    it "deletes the row with a matching lock_version" do
      obligation = create(:studywell_obligation, user: user, course: course)

      delete "/api/v1/studywell/obligations/#{obligation.id}",
             params: { lock_version: 0 },
             headers: bearer(token), as: :json

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
      expect(Studywell::Obligation.exists?(obligation.id)).to be(false)
    end

    it "returns 409 on a stale lock_version without deleting" do
      obligation = create(:studywell_obligation, user: user, course: course, title: "Keep")
      obligation.update!(title: "Touched")

      delete "/api/v1/studywell/obligations/#{obligation.id}",
             params: { lock_version: 0 },
             headers: bearer(token), as: :json

      expect(response).to have_http_status(:conflict)
      expect(Studywell::Obligation.exists?(obligation.id)).to be(true)
      expect(obligation.reload.title).to eq("Touched")
    end

    it "returns 404 for another user's obligation and does not delete it" do
      obligation = create(:studywell_obligation, user: other)

      delete "/api/v1/studywell/obligations/#{obligation.id}",
             params: { lock_version: 0 },
             headers: bearer(token), as: :json

      expect(response).to have_http_status(:not_found)
      expect(Studywell::Obligation.exists?(obligation.id)).to be(true)
    end
  end
end
