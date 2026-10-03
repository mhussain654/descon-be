# frozen_string_literal: true

module CandidateWorkflows
  class StateSnapshotService < ApplicationService
    Snapshot = Data.define(
      :candidate,
      :assignment,
      :mobilization_process,
      :candidate_status,
      :current_stage,
      :timeline,
      :history,
      :history_entries,
      :qvc_attempts,
      :protection_record,
      :medical_result,
      :visa_decision,
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

    def snapshot_attributes
      SnapshotBuilder.call(
        assignment:,
        candidate_status: @candidate.status_code,
        include_history_actor: @include_history_actor
      )
    end
  end
end
