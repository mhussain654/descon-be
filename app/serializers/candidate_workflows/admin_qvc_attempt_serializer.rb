# frozen_string_literal: true

module CandidateWorkflows
  class AdminQvcAttemptSerializer
    def initialize(attempt)
      @attempt = attempt
    end

    def as_json(*)
      QvcAttemptSerializer.new(@attempt).as_json.merge(
        internal_note: @attempt.internal_note,
        scheduled_by: serialized_actor(@attempt.scheduled_by),
        outcome_recorded_by: serialized_actor(@attempt.outcome_recorded_by)
      )
    end

    private

    def serialized_actor(actor)
      return if actor.blank?

      { id: actor.public_id, role: actor.role }
    end
  end
end
