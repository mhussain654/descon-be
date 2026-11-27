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
      MAX_ATTEMPTS = 5

      Result = Struct.new(:verified, :additional_verification_required, :locked, keyword_init: true)

      def self.call(candidate_ai_call:, params: {}) = new(candidate_ai_call:, params:).call

      def initialize(candidate_ai_call:, params: {})
        @candidate_ai_call = candidate_ai_call
        # Agents configured earlier send the number as `file_number` or `reference_number`.
        @registration_number = %w[registration_number file_number reference_number]
                               .filter_map { |key| params[key].presence }.first.to_s.strip
        @cnic = params['cnic'].presence
      end

      def call
        return Result.new(verified: true) if @candidate_ai_call.verification_status == 'verified'
        return Result.new(verified: false, locked: true) if @candidate_ai_call.verification_status == 'failed'
        return lock! if @candidate_ai_call.verification_attempts >= MAX_ATTEMPTS

        @candidate_ai_call.update!(verification_attempts: @candidate_ai_call.verification_attempts + 1)
        result = attempt_verification
        return result unless result.verified == false && @candidate_ai_call.verification_attempts >= MAX_ATTEMPTS

        lock!
      end

      private

      # The registration number names one candidate; the caller's phone number (or, failing that, their CNIC)
      # confirms it is them.
      def attempt_verification
        assignments = candidate_assignments
        return Result.new(verified: false) if assignments.empty?

        match = assignments.find { |assignment| caller_number_matches?(assignment.candidate) }
        return succeed_for(match) if match
        return Result.new(verified: false, additional_verification_required: 'cnic') if @cnic.blank?

        match = assignments.find { |assignment| cnic_matches?(assignment.candidate) }
        match ? succeed_for(match) : Result.new(verified: false)
      end

      def succeed_for(assignment) = succeed!(candidate: assignment.candidate, assignment:)

      # The current assignment with the registration number the caller gave, if any.
      def candidate_assignments
        return [] unless @registration_number.match?(::Candidates::RegistrationNumberParser::FORMAT)

        CandidateAssignment.includes(:candidate).where(registration_number: @registration_number.to_i)
                           .select { |assignment| assignment.candidate.current_assignment == assignment }
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
        link_result = ::AiCalls::LinkVerifiedCandidateService.call(
          candidate_ai_call: @candidate_ai_call, candidate:, assignment:
        )
        return Result.new(verified: false) if link_result.mismatch

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
