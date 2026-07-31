module TelegramBot
  class UpdateSerializer
    # Telegram::Bot::Types::Base#to_compact_hash only recurses into nested
    # values that themselves respond to #to_compact_hash, so it leaves raw
    # struct instances (e.g. MessageEntity) inside Array attributes like
    # Message#entities untouched. Every message starting with "/" carries a
    # bot_command entity, so that gap breaks ActiveJob serialization for
    # ordinary commands. This dumps to plain, job-serializable Ruby values.
    def self.dump(value)
      case value
      when Telegram::Bot::Types::Base
        value.attributes.each_with_object({}) do |(key, attribute_value), hash|
          next if attribute_value.nil?

          hash[key] = dump(attribute_value)
        end
      when Array
        value.map { |element| dump(element) }
      else
        value
      end
    end
  end
end
