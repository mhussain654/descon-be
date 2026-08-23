# frozen_string_literal: true

module Idempotency
  class ResponseStore
    CACHE_TTL = 12.hours
    CACHE_NAMESPACE = 'idempotency:responses'

    def initialize(cache:)
      @cache = cache
    end

    def read(key:)
      @cache.read(cache_key(key))
    end

    def write(key:, fingerprint:, response:)
      @cache.write(
        cache_key(key),
        {
          'fingerprint' => fingerprint,
          'response' => response.deep_stringify_keys
        },
        expires_in: CACHE_TTL
      )
    end

    private

    def cache_key(key)
      "#{CACHE_NAMESPACE}:#{key}"
    end
  end
end
