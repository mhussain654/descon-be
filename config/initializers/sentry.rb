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

    # Second line of defense beyond send_default_pii/filter_parameters: never forward a
    # sensitive value if it happens to have been interpolated directly into an exception
    # message, a breadcrumb (including SQL query breadcrumbs, whose bound values can carry
    # one) or custom context/extra data, at the point closest to actually leaving the process.
    #
    # Filtering only `event.message` (the previous implementation) missed the far more common
    # capture path -- an unhandled exception's text lives in `event.exception.values[].value`,
    # not `event.message` (which is only ever populated by an explicit
    # `Sentry.capture_message` call) -- so this now covers exception values, breadcrumbs and
    # contexts/extra recursively. See Observability::SentryRedaction for the actual patterns.
    config.before_send = lambda do |event, _hint|
      Observability::SentryRedaction.redact_event(event)
    end
    config.before_send_transaction = lambda do |event, _hint|
      Observability::SentryRedaction.redact_event(event)
    end
    config.before_breadcrumb = lambda do |breadcrumb, _hint|
      Observability::SentryRedaction.redact_breadcrumb(breadcrumb)
    end
  end
end
