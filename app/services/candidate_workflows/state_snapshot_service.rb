# frozen_string_literal: true

module CandidateWorkflows
  class StateSnapshotService < ApplicationService
    Snapshot = Data.define(
      :candidate,
      :assignment,
      :candidate_status,
      :current_stage,
      :timeline,
      :history,
      :completed_count,
      :total_count,
      :progress_percentage,
      :updated_at
    )

    def initialize(candidate:)
      @candidate = candidate
    end

    def call
      Snapshot.new(candidate: @candidate, assignment:, candidate_status: @candidate.status_code, **snapshot_attributes)
    end

    private

    def assignment = @assignment ||= @candidate.current_assignment

    def stages = @stages ||= WorkflowStage.order(:position).to_a

    def snapshot_attributes
      SnapshotBuilder.call(
        assignment:,
        candidate_status: @candidate.status_code,
        stages:
      )
    end
  end
end
