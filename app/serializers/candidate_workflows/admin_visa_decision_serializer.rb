# frozen_string_literal: true

module CandidateWorkflows
  class AdminVisaDecisionSerializer
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
        recorded_by: serialized_actor(@decision.recorded_by),
        created_at: @decision.created_at.utc.iso8601
      }
    end

    private

    def serialized_actor(actor)
      return if actor.blank?

      { id: actor.public_id, role: actor.role }
    end
  end
end
