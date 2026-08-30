# frozen_string_literal: true

module CandidateWorkflows
  class HistorySerializer
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def as_json(*)
      {
        candidate_id: @snapshot.candidate.public_id,
        assignment_id: @snapshot.assignment&.public_id,
        history: @snapshot.history,
        updated_at: @snapshot.updated_at
      }
    end
  end
end
