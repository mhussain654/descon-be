# frozen_string_literal: true

module Observability
  # Recursive Sentry event/breadcrumb sanitization (config/initializers/sentry.rb).
  #
  # Filtering only `event.message` (the previous implementation) misses the
  # far more common capture path: an unhandled exception's text lives in
  # `event.exception.values[].value`, not `event.message`, which is only
  # ever populated by an explicit `Sentry.capture_message` call -- meaning
  # the original filter was effectively dead code for ordinary unhandled
  # exceptions. This also covers breadcrumbs (including SQL query
  # breadcrumbs, whose `message`/`data` can carry bound values) and
  # contexts/extra, recursively, since either can be arbitrarily nested.
  module SentryRedaction
    # `_` is a word character, so a literal `\b` anchor never matches between
    # it and an adjacent letter -- meaning a plain `\btoken\b`/`\bpassword\b`
    # silently fails to match `access_token`/`refresh_token`/
    # `password_confirmation`, exactly the compound key names this app
    # actually uses. The lookaround anchors below treat `_` as a valid
    # boundary on both sides, and `(?:_[a-z0-9]+)*` consumes any trailing
    # snake_case suffix (e.g. `_confirmation`) so the match still reaches the
    # `:`/`=` separator.
    SENSITIVE_KEY = '(?<![a-z0-9])(cnic|passport|otp|password|token|account_number|iban|signature)(?:_[a-z0-9]+)*'
    SENSITIVE_KEY_VALUE_PATTERN = /#{SENSITIVE_KEY}"?\s*[:=]\s*"?[^\s&,;"'}]*/i
    JWT_PATTERN = /\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/
    CNIC_PATTERN = /\b\d{5}-?\d{7}-?\d\b/

    def self.redact_text(value)
      return value unless value.is_a?(String)

      value
        .gsub(SENSITIVE_KEY_VALUE_PATTERN) { |_match| "#{Regexp.last_match(1)}=[FILTERED]" }
        .gsub(JWT_PATTERN, '[FILTERED]')
        .gsub(CNIC_PATTERN, '[FILTERED]')
    end

    # Walks an arbitrarily-nested Hash/Array (a breadcrumb's `data`, an
    # event's `contexts`/`extra`), redacting every String leaf. Non-string
    # leaves (numbers, booleans, nil) are returned unchanged.
    def self.redact_value(value)
      case value
      when String then redact_text(value)
      when Hash then value.transform_values { |v| redact_value(v) }
      when Array then value.map { |v| redact_value(v) }
      else value
      end
    end

    def self.redact_event(event)
      event.message = redact_text(event.message) if event.message
      redact_exception_values!(event)
      event.contexts = redact_value(event.contexts) if event.respond_to?(:contexts=) && event.contexts
      event.extra = redact_value(event.extra) if event.respond_to?(:extra=) && event.extra
      event
    end

    # Only ErrorEvent (not e.g. TransactionEvent) responds to #exception at
    # all. `event.exception.values` is an Array of SingleExceptionInterface
    # (Sentry's own naming, not a Hash) -- `each_value` does not apply here.
    def self.redact_exception_values!(event)
      return unless event.respond_to?(:exception) && event.exception

      list = event.exception.values || [] # -- an Array, not a Hash, despite the #values name (Sentry::ExceptionInterface#values)
      list.each do |exception_value|
        exception_value.value = redact_text(exception_value.value) if exception_value.value
      end
    end
    private_class_method :redact_exception_values!

    def self.redact_breadcrumb(breadcrumb)
      breadcrumb.message = redact_text(breadcrumb.message) if breadcrumb.message
      breadcrumb.data = redact_value(breadcrumb.data) if breadcrumb.data
      breadcrumb
    end
  end
end
