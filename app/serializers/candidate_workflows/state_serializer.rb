# frozen_string_literal: true

module CandidateWorkflows
  class StateSerializer
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def as_json(*) = base_attributes.merge(updated_at: @snapshot.updated_at)

    private

    def base_attributes
      {
        candidate_id: @snapshot.candidate.public_id,
        assignment_id: @snapshot.assignment&.public_id,
        candidate_status: @snapshot.candidate_status,
        current_stage: @snapshot.current_stage,
        timeline: @snapshot.timeline,
        completed_count: @snapshot.completed_count,
        total_count: @snapshot.total_count,
        progress_percentage: @snapshot.progress_percentage
      }
    end
  end
end
