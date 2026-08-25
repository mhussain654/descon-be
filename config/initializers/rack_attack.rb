# frozen_string_literal: true

module Rack
  class Attack
    # Rack::Attack.cache.store defaults to Rails.cache, which is
    # config.cache_store = :null_store in the test environment -- meaning
    # no throttle below (old or new) has ever actually been able to trip in
    # a request spec, since counts are silently never persisted. Production
    # and development are unaffected and keep using Rails.cache (solid_cache
    # in production), which is a real, shared-across-process store; this
    # override only replaces the no-op null store that test uses.
    cache.store = ActiveSupport::Cache::MemoryStore.new if Rails.env.test?

    throttle('api/ip', limit: ENV.fetch('API_RATE_LIMIT_PER_MINUTE', 120).to_i, period: 1.minute) do |request|
      request.ip if request.path.start_with?('/api/')
    end

    throttle('auth/ip', limit: ENV.fetch('AUTH_RATE_LIMIT_PER_MINUTE', 20).to_i, period: 1.minute) do |request|
      request.ip if request.path.start_with?('/api/v1/auth/')
    end

    throttle(
      'auth/email',
      limit: ENV.fetch('AUTH_IDENTITY_RATE_LIMIT_PER_MINUTE', 10).to_i,
      period: 1.minute
    ) do |request|
      next unless request.post? && request.path == '/api/v1/auth/login'

      request.params.dig('auth', 'email').to_s.strip.downcase.presence
    end

    throttle(
      'auth/refresh_token',
      limit: ENV.fetch('AUTH_REFRESH_TOKEN_RATE_LIMIT_PER_MINUTE', 10).to_i,
      period: 1.minute
    ) do |request|
      next unless request.post? && request.path == '/api/v1/auth/refresh'

      refresh_token = request.params.dig('auth', 'refresh_token').to_s
      next if refresh_token.blank?

      Digest::SHA256.hexdigest(refresh_token)
    end

    throttle(
      'staff_invitation/ip',
      limit: ENV.fetch('STAFF_INVITATION_ACCEPT_RATE_LIMIT_PER_MINUTE', 10).to_i,
      period: 1.minute
    ) do |request|
      next unless request.patch? && request.path.start_with?('/api/v1/user_invitations/')

      request.ip
    end

    throttle('candidate_otp/ip', limit: ENV.fetch('OTP_RATE_LIMIT_PER_MINUTE', 10).to_i, period: 1.minute) do |request|
      request.ip if request.path.start_with?('/api/v1/candidate/auth/otp/')
    end

    throttle(
      'candidate_otp/cnic',
      limit: ENV.fetch('OTP_IDENTITY_RATE_LIMIT_PER_MINUTE', 5).to_i,
      period: 1.minute
    ) do |request|
      next unless request.post? && request.path.start_with?('/api/v1/candidate/auth/otp/')

      # Normalized so "12345-1234567-1" and "1234512345671" throttle as the
      # same identity, matching how Candidates::CnicNormalizer resolves both
      # to the same candidate.
      request.params.dig('candidate', 'cnic').to_s.gsub(/\D/, '').presence
    end

    self.throttled_responder = lambda do |request|
      retry_after = (request.env['rack.attack.match_data'] || {})[:period]
      locale = Localization::LocaleResolver.call(
        explicit_locale: request.get_header('HTTP_X_LOCALE'),
        accept_language: request.get_header('HTTP_ACCEPT_LANGUAGE')
      )
      message = I18n.t('api.errors.rate_limited', locale:)
      request_id = request.get_header('action_dispatch.request_id')
      timestamp = Time.current.utc.iso8601

      [
        429,
        {
          'Content-Type' => 'application/json',
          'Retry-After' => retry_after.to_s,
          'Content-Language' => locale.to_s,
          'Vary' => 'Accept-Language, X-Locale',
          'X-Request-Id' => request_id
        },
        [{ errors: [{ code: 'rate_limited', message: message }], request_id:, timestamp: }.to_json]
      ]
    end
  end
end
