# frozen_string_literal: true

module Rack
  class Attack
    throttle('api/ip', limit: ENV.fetch('API_RATE_LIMIT_PER_MINUTE', 120).to_i, period: 1.minute) do |request|
      request.ip if request.path.start_with?('/api/')
    end

    throttle('auth/ip', limit: ENV.fetch('AUTH_RATE_LIMIT_PER_MINUTE', 20).to_i, period: 1.minute) do |request|
      request.ip if request.path.start_with?('/api/v1/auth/')
    end

    self.throttled_responder = lambda do |request|
      retry_after = (request.env['rack.attack.match_data'] || {})[:period]

      [
        429,
        {
          'Content-Type' => 'application/json',
          'Retry-After' => retry_after.to_s
        },
        [{ errors: [{ code: 'rate_limited', message: 'Too many requests.' }] }.to_json]
      ]
    end
  end
end
