# frozen_string_literal: true

module AiCalls
  module Tools
    class GetVisaStatus < VerifiedDataTool
      private

      def data
        decision = assignment.candidate_visa_decisions.order(created_at: :desc).first
        return { status: 'pending' } if decision.blank?

        {
          outcome_code: decision.outcome_code,
          decision_date: decision.decision_date.iso8601,
          rejection_reason_code: decision.rejection_reason_code
        }
      end
    end
  end
end
