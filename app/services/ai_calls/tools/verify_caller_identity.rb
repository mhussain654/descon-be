# frozen_string_literal: true

module AiCalls
  module Tools
    # Verifies an inbound caller's identity (client-confirmed 2026-09-11):
    # reference/application number, plus CNIC only if the caller isn't
    # calling from the candidate's registered number -- not OTP (see the
    # plan's "Inbound voice identity verification" for the security
    # trade-off this implies). Available pre-verification -- it's how
    # verification happens.
    #
    # Every invocation (including a "need CNIC" prompt, not just an outright
    # failure) consumes one of MAX_ATTEMPTS -- the call-scoped hard cap is the
    # only brake on repeated guesses within one call, since (unlike OTP) there
    # is no separate SMS-side cooldown/attempt system to inherit.
    class VerifyCallerIdentity
      MAX_ATTEMPTS = 3

      Result = Struct.new(:verified, :additional_verification_required, :locked, keyword_init: true)

      def self.call(candidate_ai_call:, params: {}) = new(candidate_ai_call:, params:).call

      def initialize(candidate_ai_call:, params: {})
        @candidate_ai_call = candidate_ai_call
        @reference_number = params['reference_number'].to_s.strip
        @cnic = params['cnic'].presence
      end

      def call
        return Result.new(verified: true) if @candidate_ai_call.verification_status == 'verified'
        return Result.new(verified: false, locked: true) if @candidate_ai_call.verification_status == 'failed'

        @candidate_ai_call.update!(verification_attempts: @candidate_ai_call.verification_attempts + 1)
        return lock! if @candidate_ai_call.verification_attempts > MAX_ATTEMPTS

        attempt_verification
      end

      private

      def attempt_verification
        assignment = find_assignment
        return Result.new(verified: false) if assignment.blank?

        candidate = assignment.candidate
        return succeed!(candidate:, assignment:) if caller_number_matches?(candidate)
        return Result.new(verified: false, additional_verification_required: 'cnic') if @cnic.blank?
        return succeed!(candidate:, assignment:) if cnic_matches?(candidate)

        Result.new(verified: false)
      end

      def find_assignment
        return nil if @reference_number.blank?

        CandidateAssignment.find_by(reference_number: @reference_number.upcase)
      end

      def caller_number_matches?(candidate)
        caller_number = @candidate_ai_call.caller_number
        return false if caller_number.blank?

        secure_compare(caller_number, candidate.mobile_number)
      end

      def cnic_matches?(candidate)
        secure_compare(::Candidates::CnicNormalizer.call(@cnic), candidate.cnic)
      end

      def secure_compare(provided, expected)
        provided.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def succeed!(candidate:, assignment:)
        ::AiCalls::LinkVerifiedCandidateService.call(candidate_ai_call: @candidate_ai_call, candidate:, assignment:)
        @candidate_ai_call.update!(verification_status: 'verified')
        Result.new(verified: true)
      end

      def lock!
        @candidate_ai_call.update!(verification_status: 'failed')
        Result.new(verified: false, locked: true)
      end
    end
  end
end
