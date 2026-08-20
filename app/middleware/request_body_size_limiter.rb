# frozen_string_literal: true

class RequestBodySizeLimiter
  def initialize(app, max_body_size:)
    @app = app
    @max_body_size = max_body_size
  end

  def call(env)
    content_length = env['CONTENT_LENGTH'].to_i
    return too_large if content_length > @max_body_size

    @app.call(env)
  end

  private

  def too_large
    [
      413,
      { 'Content-Type' => 'application/json' },
      [{ errors: [{ code: 'payload_too_large', message: 'Request body is too large.' }] }.to_json]
    ]
  end
end
