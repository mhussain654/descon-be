# frozen_string_literal: true

module AiCalls
  module Tools
    # Available pre-verification. No live transfer destination exists yet
    # (blocked on Trello MPS-709 -- the client hasn't given an escalation
    # number/hours) -- until that lands, this deliberately degrades to
    # logging the same signal CreateCallbackRequest would, rather than
    # attempting to connect the live call to a destination that doesn't
    # exist. Swap this for a real telephony transfer once MPS-709 answers.
    class TransferToHuman
      def self.call(candidate_ai_call:, params: {}) = new(candidate_ai_call:, params:).call

      def initialize(candidate_ai_call:, params: {})
        @candidate_ai_call = candidate_ai_call
        @reason = params['reason'].to_s.strip.presence
      end

      def call
        @candidate_ai_call.update!(callback_requested_at: Time.current)
        { transfer_available: false, callback_requested: true, reason: @reason }.compact
      end
    end
  end
end
