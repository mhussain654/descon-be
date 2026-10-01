# frozen_string_literal: true

module AiCalls
  module Tools
    # Base for the 7 data-retrieval tools. Independently re-checks
    # verification server-side before returning anything -- never trusts
    # that the agent already decided verification succeeded (defense in
    # depth against a jailbroken/misbehaving agent). Verification means
    # different things per flow (see the plan's "Verification requirement,
    # precisely stated"):
    # - inbound: verification_status must be 'verified' (OTP-less
    #   reference-number+CNIC check, see VerifyCallerIdentityService).
    # - outbound (admin-triggered or workflow-stage-triggered): dialing the
    #   candidate's own registered number is the assurance mechanism, so
    #   'not_applicable'/'skipped' are already sufficient.
    class VerifiedDataTool
      # `params` is accepted (and ignored by every data-retrieval subclass)
      # only so AiCalls::Tools::Registry can dispatch every tool -- data
      # tools and the argument-taking ones (verify_caller_identity,
      # create_callback_request) -- through one uniform call signature.
      def self.call(candidate_ai_call:, params: {}) = new(candidate_ai_call:, params:).call

      def initialize(candidate_ai_call:, params: {})
        @candidate_ai_call = candidate_ai_call
        @params = params
      end

      def call
        return { error: 'not_verified' } unless verified?
        return { error: 'no_assignment' } if assignment.blank?

        data
      end

      private

      attr_reader :candidate_ai_call

      def verified?
        if candidate_ai_call.direction == 'inbound'
          candidate_ai_call.verification_status == 'verified'
        else
          candidate_ai_call.verification_status.in?(%w[not_applicable skipped])
        end
      end

      def candidate = candidate_ai_call.candidate

      def assignment = candidate_ai_call.candidate_assignment

      def data
        raise NotImplementedError
      end
    end
  end
end
