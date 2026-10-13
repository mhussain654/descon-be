# frozen_string_literal: true

allowed_origins =
  if Rails.env.production?
    ENV.fetch('CORS_ALLOWED_ORIGINS')
  else
    ENV.fetch('CORS_ALLOWED_ORIGINS', 'http://localhost:3000,http://localhost:3001,https://b781-2400-adc5-424-2200-434-2336-4a6f-a106.ngrok-free.app')
  end

trusted_frontend_origins = allowed_origins.split(',').map(&:strip).compact_blank
# The same trusted frontends may embed private file previews (e.g. a PDF in
# the admin document review) -- see SecurityHeadersMiddleware.
Rails.application.config.x.trusted_frontend_origins = trusted_frontend_origins

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*trusted_frontend_origins)

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: %w[X-Request-Id],
             max_age: 600
  end
end
