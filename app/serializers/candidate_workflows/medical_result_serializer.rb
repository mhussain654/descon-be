# frozen_string_literal: true

module CandidateWorkflows
  # Candidate-safe shape of a medical result: outcome and date only -- never
  # staff notes or identity.
  class MedicalResultSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        id: @result.public_id,
        outcome_code: @result.outcome_code,
        result_date: @result.result_date.iso8601,
        re_decision: @result.candidate_stage_history_id.nil?,
        created_at: @result.created_at.utc.iso8601
      }
    end
  end
end
