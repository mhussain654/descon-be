# frozen_string_literal: true

module Admin
  # A durable, allowlist-based filter for AuditEvent#metadata, applied at the
  # serializer boundary rather than trusted to every existing/future
  # *AuditRecorder writer -- "every current call site happens to write only
  # safe fields" is not a security boundary, since it silently stops being
  # true the moment one new recorder writes something free-form.
  #
  # Deny by default: an unrecognized key is dropped, never shown -- adding a
  # new *AuditRecorder metadata field means deliberately approving it here
  # first, rather than it rendering by default and risking a future
  # sensitive value reaching the audit explorer unnoticed.
  module AuditEventMetadataSanitizer
    # A handful of *AuditRecorder call sites store a free-typed value under
    # these keys (a staff-entered investigation `reason`, the raw
    # `previous_value`/`new_value` of a corrected payment field, or an
    # arbitrary-shaped `before`/`after`/`details`/`evidence` hash) -- never
    # approved for display, even though no current writer happens to put
    # anything sensitive there today.
    BLOCKED_KEYS = %w[reason field previous_value new_value before after details evidence].freeze

    # Every other metadata key observed across this app's *AuditRecorder
    # classes follows one of these suffixes: opaque public UUIDs (_id/_ids),
    # enum/status codes (_code/_codes), timestamps/dates (_at/_on/_date/
    # _dates), or counts (_count/_counts/_rows/_number/_numbers/_version).
    SAFE_KEY_SUFFIXES = %w[
      _id _ids _code _codes _at _on _date _dates _count _counts _rows _number _numbers _version
    ].freeze

    # A handful of exact names don't fit a suffix (flight logistics,
    # booleans) and are listed explicitly.
    SAFE_EXACT_KEYS = %w[airline flight_number sector no_show conflict replaced file_fingerprint action code].freeze

    def self.sanitize(metadata)
      return {} if metadata.blank?

      metadata.each_with_object({}) do |(key, value), result|
        next unless approved_key?(key.to_s)

        result[key] = safe_value(value)
      end
    end

    def self.approved_key?(key)
      return false if BLOCKED_KEYS.include?(key)
      return true if SAFE_EXACT_KEYS.include?(key)

      SAFE_KEY_SUFFIXES.any? { |suffix| key.end_with?(suffix) }
    end
    private_class_method :approved_key?

    # Never returns a Hash/Array-of-Hashes as-is -- an approved *key* is not
    # a guarantee about the *shape* of whatever value ends up under it if a
    # future writer's field type changes.
    def self.safe_value(value)
      case value
      when String, Numeric, true, false, nil
        value
      when Array
        value.all? { |item| item.is_a?(String) || item.is_a?(Numeric) } ? value : "(#{value.size} items)"
      else
        '(unavailable)'
      end
    end
    private_class_method :safe_value
  end
end
