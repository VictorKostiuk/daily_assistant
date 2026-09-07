class SourceMetadata
  FIELDS = %w[context_type source_app source_entity_type source_entity_id].freeze
  CONTEXT_TYPES = %w[life study work global].freeze

  class Invalid < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("Request is invalid")
    end

    def error_envelope
      {
        "error" => {
          "code" => "validation_error",
          "message" => "Request is invalid",
          "details" => details
        }
      }
    end

    def http_status
      :unprocessable_content
    end
  end

  def self.dump(attrs)
    merge({}, attrs)
  end

  # Merge the supplied source fields into existing metadata.
  # Omitted keys are preserved; explicit nils clear that source field only;
  # unrelated metadata keys are left untouched.
  def self.merge(existing_metadata, attrs)
    return existing_copy(existing_metadata) if attrs.blank?
    raise Invalid.new("metadata" => [ "is invalid" ]) unless attrs.is_a?(Hash)

    attrs = attrs.stringify_keys
    unknown = attrs.keys - FIELDS
    raise Invalid.new(unknown.index_with { [ "is unknown" ] }) if unknown.any?

    details = {}
    attrs.each do |key, value|
      next if value.nil?

      if !value.is_a?(String) || value.strip.empty?
        details[key] = [ "is invalid" ]
      elsif key == "context_type" && CONTEXT_TYPES.exclude?(value)
        details[key] = [ "is not included in the list" ]
      end
    end
    raise Invalid.new(details) if details.any?

    existing = existing_copy(existing_metadata)
    source = (existing["source"] || {}).stringify_keys
    attrs.each do |key, value|
      if value.nil?
        source.delete(key)
      else
        source[key] = value
      end
    end

    if source.empty?
      existing.delete("source")
    else
      existing["source"] = source
    end
    existing
  end

  def self.load(metadata)
    return {} if metadata.blank?

    source = metadata.stringify_keys["source"]
    return {} if source.blank?

    source.stringify_keys.slice(*FIELDS)
  end

  def self.existing_copy(existing_metadata)
    return {} if existing_metadata.blank?

    existing_metadata.deep_dup.stringify_keys
  end
  private_class_method :existing_copy
end
