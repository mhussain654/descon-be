# frozen_string_literal: true

module CandidateWorkflows
  class ProtectionScheduleQuery < ApplicationQuery
    def initialize(scope: CandidateProtectionRecord.all)
      super()
      @scope = scope
    end

    def call
      @scope
        .includes(candidate_assignment: :candidate)
        .where.not(appeared_on: nil)
        .where(ready_to_fly_at: nil)
        .order(:appeared_on, :id)
    end
  end
end
