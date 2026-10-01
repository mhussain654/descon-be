# frozen_string_literal: true

module CandidateWorkflows
  # Candidate-facing shape for a visa decision -- unlike
  # AdminVisaDecisionSerializer, this never includes `recorded_by` (the
  # staff actor who recorded it isn't the candidate's business).
  class VisaDecisionSerializer
    def initialize(decision)
      @decision = decision
    end

    def as_json(*)
      {
        id: @decision.public_id,
        outcome_code: @decision.outcome_code,
        decision_date: @decision.decision_date.iso8601,
        rejection_reason_code: @decision.rejection_reason_code,
        visa_copy_attached: @decision.visa_copy.attached?,
        created_at: @decision.created_at.utc.iso8601
      }
    end
  end
end
