require "rails_helper"
require "set"
require "yaml"

# Compares the live /api/v1 (path, verb) surface to docs/openapi.yaml.
# Both sides are computed. There is no hand-maintained list of paths.
# Schemas and examples are not checked here — they were derived by a
# manual read of the request specs and controllers.
OPENAPI_HTTP_METHODS = %w[get put post delete options head patch trace].freeze

RSpec.describe "OpenAPI /api/v1 surface" do
  def live_operations
    Rails.application.routes.routes.each_with_object(Set.new) do |route, set|
      path = route.path.spec.to_s.sub(/\(.:format\)\z/, "")
      next unless path.start_with?("/api/v1")

      path = path.gsub(":id", "{id}")
      verbs_for(route).each { |verb| set << [ path, verb ] }
    end
  end

  def documented_operations
    spec = YAML.safe_load_file(Rails.root.join("docs/openapi.yaml"))
    spec.fetch("paths").each_with_object(Set.new) do |(path, item), set|
      next unless item.is_a?(Hash)

      OPENAPI_HTTP_METHODS.each do |verb|
        set << [ path, verb ] if item.key?(verb)
      end
    end
  end

  def verbs_for(route)
    raw = route.verb
    source = raw.respond_to?(:source) ? raw.source : raw.to_s
    source.gsub(/[$^]/, "").split("|").map { |verb| verb.downcase }.reject(&:blank?)
  end

  def format_ops(ops)
    ops.sort.map { |path, verb| "#{verb.upcase} #{path}" }.join("\n")
  end

  it "matches the live /api/v1 (path, verb) surface in both directions" do
    live = live_operations
    documented = documented_operations

    documented_but_not_exposed = documented - live
    exposed_but_not_documented = live - documented

    expect(documented_but_not_exposed).to be_empty,
      "documented but not exposed:\n#{format_ops(documented_but_not_exposed)}"
    expect(exposed_but_not_documented).to be_empty,
      "exposed but not documented:\n#{format_ops(exposed_but_not_documented)}"
  end
end
