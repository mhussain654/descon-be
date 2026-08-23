# frozen_string_literal: true

module Idempotency
  class ResponsePayload
    def self.load(payload)
      normalized = payload.deep_symbolize_keys
      normalized[:type] = normalized[:type]&.to_sym
      normalized[:status] = normalized[:status]&.to_sym
      normalized
    end
  end
end
