require "rails_helper"

RSpec.describe "API v1 StudyWell courses", type: :request do
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
      [ "plain text", "Algorithms", true, true ],
      [ "ASCII space", " ", false, false ],
      [ "tab and newline", "\t\n", false, false ],
      [ "NBSP", "\u00A0", false, true ],
      [ "ideographic space", "\u3000", false, true ],
      [ "NUL", "\u0000", false, false ],
      [ "NBSP plus text", "\u00A0Keep", true, true ],
      [ "NUL plus NBSP", "\u0000\u00A0", true, true ]
    ]
  end

  def course_payload(course)
    {
      "id" => course.id,
      "name" => course.name,
      "code" => course.code,
      "term_label" => course.term_label,
      "colour" => course.colour,
      "active_from" => course.active_from&.iso8601,
      "active_until" => course.active_until&.iso8601,
      "archived_at" => course.archived_at&.iso8601,
      "lock_version" => course.lock_version
    }
  end

  let(:user) { create(:user) }
  let(:token) { issue_token_for(user) }
  let(:other) { create(:user) }

  describe "POST /api/v1/studywell/courses" do
    it "creates a course and returns the allowlisted shape with lock_version 0" do
      expect {
        post "/api/v1/studywell/courses",
             params: {
               name: "Algorithms",
               code: "CS101",
               term_label: "Fall 2026",
               colour: "#336699",
               active_from: "2026-09-01",
               active_until: "2026-12-15"
             },
             headers: bearer(token), as: :json
      }.to change { user.studywell_courses.count }.by(1)

      course = user.studywell_courses.order(:id).last
      expect(response).to have_http_status(:created)
      expect(json).to eq(course_payload(course))
      expect(json["lock_version"]).to eq(0)
      expect(course.name).to eq("Algorithms")
      expect(course.active_from).to eq(Date.iso8601("2026-09-01"))
    end

    it "stores omitted optional fields as null" do
      post "/api/v1/studywell/courses", params: { name: "Bare" }, headers: bearer(token), as: :json

      expect(response).to have_http_status(:created)
      course = user.studywell_courses.order(:id).last
      expect(course.code).to be_nil
      expect(json["code"]).to be_nil
      expect(json["archived_at"]).to be_nil
    end

    it "rejects a blank name, invalid colour, unordered dates, and unknown keys without inserting" do
      [
        { name: "  " },
        { name: "X", colour: "336699" },
        { name: "X", active_from: "2026-12-01", active_until: "2026-01-01" },
        { name: "X", user_id: other.id },
        { name: "X", archived: true }
      ].each do |params|
        expect {
          post "/api/v1/studywell/courses", params: params, headers: bearer(token), as: :json
        }.not_to change(Studywell::Course, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_error")
      end
    end

    it "rejects a wrong-type optional field rather than treating it as omitted" do
      expect {
        post "/api/v1/studywell/courses",
             params: { name: "Typed", code: 1 },
             headers: bearer(token), as: :json
      }.not_to change(Studywell::Course, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("code")
    end

    it "records server and schema-instance outcomes for create names separately" do
      schema = openapi_schema("StudywellCourseCreate").fetch("properties").fetch("name")
      schema_rejected_but_server_accepted = []
      nonblank_cases.each do |label, value, server_accepts, schema_accepts|
        instance_ok = schema_instance_accepts?(schema, value)
        expect(instance_ok).to eq(schema_accepts),
          "#{label}: schema-instance #{instance_ok.inspect}, expected #{schema_accepts.inspect}"
        expect([ "NBSP", "ideographic space" ]).to include(label) if schema_accepts && !server_accepts

        expect {
          post "/api/v1/studywell/courses", params: { name: value }, headers: bearer(token), as: :json
        }.to change { user.studywell_courses.count }.by(server_accepts ? 1 : 0)

        if server_accepts
          expect(response).to have_http_status(:created)
          expect(user.studywell_courses.order(:id).last.name).to eq(value)
        else
          expect(response).to have_http_status(:unprocessable_content)
        end
        schema_rejected_but_server_accepted << label if !instance_ok && server_accepts
      end
      expect(schema_rejected_but_server_accepted).to eq([])
    end
  end

  describe "GET /api/v1/studywell/courses" do
    it "lists only the caller's non-archived courses in id order" do
      first = create(:studywell_course, user: user, name: "First")
      second = create(:studywell_course, user: user, name: "Second")
      archived = create(:studywell_course, :archived, user: user, name: "Old")
      create(:studywell_course, user: other, name: "Not yours")

      get "/api/v1/studywell/courses", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json["items"].map { |item| item["id"] }).to eq([ first.id, second.id ])
      expect(json["items"].map { |item| item["name"] }).not_to include("Old", "Not yours")
      expect(json["next_page"]).to be_nil
      expect(Studywell::Course.exists?(archived.id)).to be(true)
    end

    it "includes archived courses only when include_archived is the string true" do
      create(:studywell_course, user: user, name: "Active")
      create(:studywell_course, :archived, user: user, name: "Old")

      get "/api/v1/studywell/courses", params: { include_archived: "true" }, headers: bearer(token)
      expect(json["items"].map { |item| item["name"] }).to contain_exactly("Active", "Old")

      get "/api/v1/studywell/courses", params: { include_archived: "false" }, headers: bearer(token)
      expect(json["items"].map { |item| item["name"] }).to eq([ "Active" ])
    end

    it "rejects any other present include_archived value and ignores unknown query keys" do
      get "/api/v1/studywell/courses", params: { include_archived: "yes" }, headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("include_archived")

      get "/api/v1/studywell/courses", params: { extra: "1" }, headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end

    it "treats a present valueless include_archived as invalid, unlike an omitted key" do
      create(:studywell_course, user: user, name: "Active")
      create(:studywell_course, :archived, user: user, name: "Old")

      get "/api/v1/studywell/courses", headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(json["items"].map { |item| item["name"] }).to eq([ "Active" ])

      get "/api/v1/studywell/courses?include_archived=true", headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(json["items"].map { |item| item["name"] }).to contain_exactly("Active", "Old")

      get "/api/v1/studywell/courses?include_archived", headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("include_archived")

      get "/api/v1/studywell/courses?include_archived=", headers: bearer(token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("include_archived")
    end

    it "leaves a present valueless page as the shipped default, including on reminders" do
      get "/api/v1/studywell/courses?page", headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(json).to include("items", "next_page")

      get "/api/v1/reminders?page", headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(json).to include("items", "next_page")
    end

    it "pages 100 at a time and sets next_page on a truncated page" do
      create_list(:studywell_course, 101, user: user)

      get "/api/v1/studywell/courses", headers: bearer(token)
      expect(response).to have_http_status(:ok)
      expect(json["items"].size).to eq(100)
      expect(json["next_page"]).to eq(2)

      get "/api/v1/studywell/courses", params: { page: 2 }, headers: bearer(token)
      expect(json["items"].size).to eq(1)
      expect(json["next_page"]).to be_nil
      expect(user.studywell_courses.count).to eq(101)
    end
  end

  describe "GET /api/v1/studywell/courses/:id" do
    it "returns the caller's course including an archived one" do
      course = create(:studywell_course, :archived, user: user)

      get "/api/v1/studywell/courses/#{course.id}", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(course_payload(course.reload))
    end

    it "returns 404 for another user's course" do
      course = create(:studywell_course, user: other)

      get "/api/v1/studywell/courses/#{course.id}", headers: bearer(token)

      expect(response).to have_http_status(:not_found)
      expect(json.dig("error", "code")).to eq("not_found")
    end
  end

  describe "PATCH /api/v1/studywell/courses/:id" do
    let(:course) { create(:studywell_course, user: user, name: "Old", code: "KEEP", colour: "#111111") }

    it "updates submitted fields, preserves omitted ones, and increments lock_version from 0" do
      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 0, name: "New" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:ok)
      reloaded = course.reload
      expect(reloaded.name).to eq("New")
      expect(reloaded.code).to eq("KEEP")
      expect(reloaded.lock_version).to eq(1)
      expect(json["lock_version"]).to eq(1)
      expect(json["code"]).to eq("KEEP")
    end

    it "records server and schema-instance outcomes for PATCH names separately" do
      schema = openapi_schema("StudywellCoursePatch").fetch("properties").fetch("name")
      schema_rejected_but_server_accepted = []
      nonblank_cases.each do |label, value, server_accepts, schema_accepts|
        instance_ok = schema_instance_accepts?(schema, value)
        expect(instance_ok).to eq(schema_accepts),
          "#{label}: schema-instance #{instance_ok.inspect}, expected #{schema_accepts.inspect}"
        expect([ "NBSP", "ideographic space" ]).to include(label) if schema_accepts && !server_accepts

        record = create(:studywell_course, user: user, name: "Old")
        patch "/api/v1/studywell/courses/#{record.id}",
              params: { lock_version: 0, name: value },
              headers: bearer(token), as: :json

        if server_accepts
          expect(response).to have_http_status(:ok)
          expect(record.reload.name).to eq(value)
        else
          expect(response).to have_http_status(:unprocessable_content)
          expect(record.reload.name).to eq("Old")
          expect(record.lock_version).to eq(0)
        end
        schema_rejected_but_server_accepted << label if !instance_ok && server_accepts
      end
      expect(schema_rejected_but_server_accepted).to eq([])
    end

    it "clears a nullable field given explicit null and rejects a wrong type without changing the row" do
      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 0, code: nil },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(course.reload.code).to be_nil

      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 1, colour: 12 },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details")).to include("colour")
      expect(course.reload.colour).to eq("#111111")
    end

    it "rejects clearing name, unknown keys, empty updates, and a string lock_version" do
      original = course.attributes

      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 0, name: nil },
            headers: bearer(token), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(course.reload.name).to eq("Old")

      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 0, archived_at: Time.current.iso8601 },
            headers: bearer(token), as: :json
      expect(json.dig("error", "details")).to include("archived_at")

      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 0 },
            headers: bearer(token), as: :json
      expect(json.dig("error", "details")).to include("base")

      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: "0", name: "Nope" },
            headers: bearer(token), as: :json
      expect(json.dig("error", "details")).to include("lock_version")
      expect(course.reload.attributes.slice("name", "code", "lock_version")).to eq(original.slice("name", "code", "lock_version"))
    end

    it "archives and unarchives without touching obligations, preserving the original archived_at" do
      create(:studywell_obligation, user: user, course: course)

      freeze_time do
        patch "/api/v1/studywell/courses/#{course.id}",
              params: { lock_version: 0, archived: true },
              headers: bearer(token), as: :json
        expect(response).to have_http_status(:ok)
        archived_at = course.reload.archived_at
        expect(archived_at).to eq(Time.current)
        expect(course.obligations.count).to eq(1)
        version = json["lock_version"]

        patch "/api/v1/studywell/courses/#{course.id}",
              params: { lock_version: version, archived: true },
              headers: bearer(token), as: :json
        expect(response).to have_http_status(:ok)
        expect(course.reload.archived_at).to eq(archived_at)

        patch "/api/v1/studywell/courses/#{course.id}",
              params: { lock_version: json["lock_version"], archived: false },
              headers: bearer(token), as: :json
        expect(response).to have_http_status(:ok)
        expect(course.reload.archived_at).to be_nil
        expect(course.obligations.count).to eq(1)
      end
    end

    it "returns 409 on a stale lock_version and leaves persisted values unchanged" do
      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 0, name: "First" },
            headers: bearer(token), as: :json
      expect(course.reload.name).to eq("First")
      expect(course.lock_version).to eq(1)

      patch "/api/v1/studywell/courses/#{course.id}",
            params: { lock_version: 0, name: "Stale" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json).to eq("error" => { "code" => "conflict", "message" => "Conflict", "details" => {} })
      expect(course.reload.name).to eq("First")
      expect(course.lock_version).to eq(1)
    end

    it "returns 404 for another user's course and does not change it" do
      theirs = create(:studywell_course, user: other, name: "Theirs")

      patch "/api/v1/studywell/courses/#{theirs.id}",
            params: { lock_version: 0, name: "Hijack" },
            headers: bearer(token), as: :json

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload.name).to eq("Theirs")
    end
  end

  describe "DELETE /api/v1/studywell/courses/:id" do
    it "deletes an empty course with a matching lock_version" do
      course = create(:studywell_course, user: user)

      delete "/api/v1/studywell/courses/#{course.id}",
             params: { lock_version: 0 },
             headers: bearer(token), as: :json

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
      expect(Studywell::Course.exists?(course.id)).to be(false)
    end

    it "returns 409 with obligations_count and does not delete while obligations exist" do
      course = create(:studywell_course, user: user)
      create_list(:studywell_obligation, 2, user: user, course: course)

      delete "/api/v1/studywell/courses/#{course.id}",
             params: { lock_version: 0 },
             headers: bearer(token), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json).to eq(
        "error" => {
          "code" => "conflict",
          "message" => "Conflict",
          "details" => { "obligations_count" => 2 }
        }
      )
      expect(Studywell::Course.exists?(course.id)).to be(true)
      expect(course.obligations.count).to eq(2)
    end

    it "returns 409 on a stale lock_version without deleting" do
      course = create(:studywell_course, user: user)
      course.update!(name: "Touched")

      delete "/api/v1/studywell/courses/#{course.id}",
             params: { lock_version: 0 },
             headers: bearer(token), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "details")).to eq({})
      expect(Studywell::Course.exists?(course.id)).to be(true)
      expect(course.reload.name).to eq("Touched")
    end

    it "returns 404 for another user's course and does not delete it" do
      course = create(:studywell_course, user: other)

      delete "/api/v1/studywell/courses/#{course.id}",
             params: { lock_version: 0 },
             headers: bearer(token), as: :json

      expect(response).to have_http_status(:not_found)
      expect(Studywell::Course.exists?(course.id)).to be(true)
    end
  end
end
