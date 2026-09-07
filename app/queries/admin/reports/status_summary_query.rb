# frozen_string_literal: true

module Admin
  module Reports
    # Status-wise candidate counts across all 15 canonical workflow stages
    # (MPS-804). Every stage is represented in the output, zero-filled when
    # no candidate is currently there -- callers must never need to guess
    # whether a missing key means zero or "not computed".
    class StatusSummaryQuery < ApplicationQuery
      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        counts = counts_by_stage_id
        WorkflowStage::CANONICAL_STAGES.map do |stage|
          stage_id = workflow_stage_ids.fetch(stage.fetch(:code))
          { code: stage.fetch(:code), position: stage.fetch(:position), count: counts.fetch(stage_id, 0) }
        end
      end

      private

      def counts_by_stage_id
        CurrentAssignmentJoin.call(scope: @scope).group('current_assignments.current_workflow_stage_id').count
      end

      def workflow_stage_ids
        @workflow_stage_ids ||= WorkflowStage.pluck(:code, :id).to_h
      end
    end
  end
end
