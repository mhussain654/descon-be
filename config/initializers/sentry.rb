# frozen_string_literal: true

# Wires up the sentry-rails/sentry-ruby gems (MPS-904) -- both were already in the Gemfile, but
# nothing ever called Sentry.init, so the RescuedExceptionInterceptor middleware already
# present in every request (visible in this app's own middleware stack) has been running
# against an unconfigured client this whole time: a safe no-op, not an error, but nothing was
# actually being reported anywhere.
#
# Gated on SENTRY_DSN being present, matching this project's established "if approved"
# credential-gated pattern (SendPK, KuickPay, AWS Textract): a no-op in dev/test/any
# environment without a real DSN, and real error reporting once the client provisions one.
if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV.fetch('SENTRY_DSN')
    config.environment = Rails.env

    # Never send request cookies/headers/IP by default -- CNIC, passport, bank and payment
    # data flow through nearly every request this app serves.
    config.send_default_pii = false

    # sentry-rails already scrubs any captured request parameters using this exact
    # Rails.application.config.filter_parameters list (see filter_parameter_logging.rb) -- no
    # separate allow/deny list to maintain here.
    config.traces_sample_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', '0.1').to_f

    # Second line of defense beyond send_default_pii/filter_parameters: never forward the raw
    # exception message verbatim if it happens to have interpolated a sensitive value directly
    # (e.g. a malformed-input error echoing back what was submitted) -- match this app's own
    # known sensitive-field names one more time, at the point closest to actually leaving the
    # process.
    sensitive_pattern = /cnic|passport|otp|password|token|account_number|iban/i
    config.before_send = lambda do |event, _hint|
      event.message = '[FILTERED]' if event.message && sensitive_pattern.match?(event.message)
      event
    end
  end
end
