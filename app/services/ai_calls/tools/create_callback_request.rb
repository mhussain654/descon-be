# frozen_string_literal: true

module AiCalls
  module Tools
    # Available pre-verification (an anonymous caller can still ask for a
    # callback) -- deliberately does not disclose or confirm any
    # candidate-specific information in doing so, and this tool alone never
    # needs to (it only records that a callback was requested).
    class CreateCallbackRequest
      def self.call(candidate_ai_call:, params: {}) = new(candidate_ai_call:, params:).call

      def initialize(candidate_ai_call:, params: {})
        @candidate_ai_call = candidate_ai_call
        @reason = params['reason'].to_s.strip.presence
      end

      def call
        @candidate_ai_call.update!(callback_requested_at: Time.current)
        { callback_requested: true, reason: @reason }.compact
      end
    end
  end
end
