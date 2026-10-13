# frozen_string_literal: true

class SecurityHeadersMiddleware
  HEADERS = {
    'X-Content-Type-Options' => 'nosniff',
    'X-Frame-Options' => 'DENY',
    'Referrer-Policy' => 'strict-origin-when-cross-origin',
    'Permissions-Policy' => 'camera=(), microphone=(), geolocation=()'
  }.freeze
  # Short-lived signed file URLs (document previews). The web app shows PDFs
  # inline in an <embed>, which browsers refuse for a DENY response, so these
  # alone may be framed -- and only by the trusted frontends CORS allows.
  FILE_PREVIEW_PATH_PREFIX = '/rails/active_storage/'

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    headers = headers.merge(HEADERS)
    allow_framing_by_trusted_frontends!(headers) if env['PATH_INFO'].to_s.start_with?(FILE_PREVIEW_PATH_PREFIX)
    [status, headers, response]
  end

  private

  def allow_framing_by_trusted_frontends!(headers)
    headers.delete('X-Frame-Options')
    headers.delete('x-frame-options')
    origins = Array(Rails.application.config.x.trusted_frontend_origins)
    headers['Content-Security-Policy'] = ['frame-ancestors', "'self'", *origins].join(' ')
  end
end
