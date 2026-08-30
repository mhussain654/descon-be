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
      :history_entries,
      :completed_count,
      :total_count,
      :progress_percentage,
      :updated_at
    )

    def initialize(candidate:, include_history_actor: false)
      @candidate = candidate
      @include_history_actor = include_history_actor
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
        stages:,
        include_history_actor: @include_history_actor
      )
    end
  end
end
