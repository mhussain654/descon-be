# frozen_string_literal: true

allowed_origins = ENV.fetch('CORS_ALLOWED_ORIGINS', 'http://localhost:3000,http://localhost:3001')

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins.split(',').map(&:strip))

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: %w[X-Request-Id],
             max_age: 600
  end
end
